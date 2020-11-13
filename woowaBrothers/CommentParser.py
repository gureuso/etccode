# -*- coding: utf-8 -*-
import json
import os
import operator
import requests
import re
import xlrd


class People(object):
    @classmethod
    def getCities(cls):
        cities = [u"경남", u"경북", u"전남", u"전북", u"충남", u"충북"]

        def push(data):
            if data is None:
                return
            if data in cities:
                return
            cities.append(data)

        path = os.path.dirname(os.path.abspath(__file__)) + "/people.xls"
        book = xlrd.open_workbook(path)
        sheet = book.sheet_by_index(0)
        for rowx in range(3, sheet.nrows):
            data = sheet.cell_value(rowx=rowx, colx=0)

            firstData = re.sub("\s+\(\d+\)", "", data)
            push(firstData)

            arr = firstData.split(" ")
            if len(arr) == 1:
                secondData = re.sub(ur"(특별시|광역시|특별자치시|특별자치도|도)", "", arr[0])
            elif len(arr) == 2:
                secondData = arr[1][:-1] if len(arr[1]) > 2 else arr[1]
            else:
                secondData = None
            push(secondData)
        return cities


class School(object):
    @classmethod
    def getSchoolNames(cls):
        schoolNames = []
        path = os.path.dirname(os.path.abspath(__file__)) + "/schools.xlsx"
        book = xlrd.open_workbook(path)
        sheet = book.sheet_by_index(0)
        for rowx in range(1, sheet.nrows):
            schoolName = sheet.cell_value(rowx=rowx, colx=4)
            schoolNames.append(schoolName)
        return schoolNames

    @classmethod
    def getSchools(cls):
        """
        {
          "result": {"schoolName": 0},
          "alreadyVoteUserIds": {"userId": 0},
          "alreadyCheckCommentIds": {"CommentId": 0},
        }
        """
        path = os.path.dirname(os.path.abspath(__file__)) + "/schools.json"
        try:
            with open(path, 'r') as f:
                data = json.load(f)
        except IOError:
            open(path, 'w')
            data = {"result": {}, "alreadyVoteUserIds": {}, "alreadyCheckCommentIds": {}}
        return data

    @classmethod
    def setSchools(cls, data):
        path = os.path.dirname(os.path.abspath(__file__)) + "/schools.json"
        with open(path, 'w') as fileData:
            json.dump(data, fileData, indent=2)


class CommentParser(object):
    def __init__(self, objectId):
        self.accessToken = os.getenv("ACCESS_TOKEN", "ACCESS_TOKEN")
        self.objectId = objectId
        self.schoolNames = School.getSchoolNames()
        self.cities = People.getCities()

        schools = School.getSchools()
        self.result = schools["result"]
        self.alreadyVoteUserIds = schools["alreadyVoteUserIds"]
        self.alreadyCheckCommentIds = schools["alreadyCheckCommentIds"]

    def perform(self):
        count = 0
        nextUrl = None
        beforeData = None
        while True:
            res = self.getData(nextUrl)
            if res.get("error"):
                print beforeData
                print res
                print nextUrl
                break

            for data in res["data"]:
                count += 1
                print "count: {0}".format(count)
                self.setData(data)
                comments = data.get("comments")
                if comments:
                    for comment in comments["data"]:
                        count += 1
                        print "count: {0}".format(count)
                        self.setData(comment)

            beforeData = res
            nextUrl = res["paging"].get("next")
            if not nextUrl:
                break

        schools = sorted(self.result.items(), key=operator.itemgetter(1), reverse=True)
        for school in schools:
            print "{}: {}".format(school[0].encode("utf-8"), school[1])

    def getData(self, nextUrl=None):
        params = {
            "access_token": self.accessToken,
            "limit": 100,
            "fields": "id,from,message,comments{id,from,message,comments}"
        }
        url = nextUrl or "https://graph.facebook.com/v2.9/{0}/comments".format(self.objectId)
        res = requests.get(url, params)
        return json.loads(res.content)

    def setData(self, data):
        commentId = data["id"]
        message = data["message"]
        userId = data["from"]["id"]

        if self.alreadyVoteUserIds.get(userId):
            return
        if self.alreadyCheckCommentIds.get(commentId):
            return

        for schoolName in self.schoolNames:
            if schoolName in message:
                for city in self.cities:
                    message = message.replace(schoolName, "")
                    if city in message:
                        self.setSchool(schoolName)
                        self.setAlreadyVoteUserId(userId)
                        self.setAlreadyCheckCommentId(commentId)
                        self.setSchools()

    def setAlreadyVoteUserId(self, userId):
        count = self.alreadyVoteUserIds.get(userId, 0)
        count += 1
        self.alreadyVoteUserIds[userId] = count

    def setAlreadyCheckCommentId(self, commentId):
        count = self.alreadyCheckCommentIds.get(commentId, 0)
        count += 1
        self.alreadyCheckCommentIds[commentId] = count

    def setSchool(self, schoolName):
        school = self.result.get(schoolName)
        count = 1 if not school else school + 1
        self.result[schoolName] = count

    def setSchools(self):
        data = {
            "result": self.result,
            "alreadyVoteUserIds": self.alreadyVoteUserIds,
            "alreadyCheckCommentIds": self.alreadyCheckCommentIds
        }
        School.setSchools(data)

parser = CommentParser("1474971405859499")
parser.perform()
