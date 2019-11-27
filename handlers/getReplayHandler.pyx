import os
import sys
import traceback

import tornado.gen
import tornado.web
from raven.contrib.tornado import SentryMixin

from common.log import logUtils as log
from common.ripple import userUtils
from common.web import requestsManager
from constants import exceptions
from common.constants import mods
from objects import glob
from common.sentry import sentry

MODULE_NAME = "get_replay"
class handler(requestsManager.asyncRequestHandler):
	"""
	Handler for osu-getreplay.php
	"""
	@tornado.web.asynchronous
	@tornado.gen.engine
	@sentry.captureTornado
	def asyncGet(self):
		try:
			# Get request ip
			ip = self.getRequestIP()

			# Check arguments
			if not requestsManager.checkArguments(self.request.arguments, ["c", "u", "h"]):
				raise exceptions.invalidArgumentsException(MODULE_NAME)

			# Get arguments
			username = self.get_argument("u")
			password = self.get_argument("h")
			replayID = self.get_argument("c")



			# Login check
			userID = userUtils.getID(username)
			if userID == 0:
				raise exceptions.loginFailedException(MODULE_NAME, userID)
			if not userUtils.checkLogin(userID, password, ip):
				raise exceptions.loginFailedException(MODULE_NAME, username)
			if userUtils.check2FA(userID, ip):
				raise exceptions.need2FAException(MODULE_NAME, username, ip)
			
			if int(replayID) < 5000000:
				replayData = glob.db.fetch("SELECT scores.*, users.username AS uname FROM scores LEFT JOIN users ON scores.userid = users.id WHERE scores.id = {}".format(replayID))
				filepath = ".data/replays/"
				watchName = ""
				replayName = "[REG]"
			elif int(replayID) < 9999999:
				replayData = glob.db.fetch("SELECT scores_relax.*, users.username AS uname FROM scores_relax LEFT JOIN users ON scores_relax.userid = users.id WHERE scores_relax.id = {}".format(replayID))
				filepath = ".data/replays_relax/"
				watchName = "rx"
				replayName = "[RELAX]"
			else:
				if int(replayID) >= 10000000:
					replayData = glob.db.fetch("SELECT scores_auto.*, users.username AS uname FROM scores_auto LEFT JOIN users ON scores_auto.userid = users.id WHERE scores_auto.id = {}".format(replayID))
					filepath = ".data/replays_auto/"
					watchName = "ap"
					replayName = "[AP]"
				
			# Increment 'replays watched by others' if needed
			if replayData is not None:
				if username != replayData["uname"]:
					userUtils.incrementReplaysWatched(replayData["userid"], replayData["play_mode"], watchName)
			log.info("Serving {}replay_{}.osr for {}".format(filepath, replayID, username))
			fileName = "{}replay_{}.osr".format(filepath, replayID)
			if os.path.isfile(fileName):
				with open(fileName, "rb") as f:
					fileContent = f.read()
				self.write(fileContent)
			else:
				self.write("")
				log.warning("Replay {}replay_{}.osr doesn't exist.".format(filepath, replayID))

		except exceptions.invalidArgumentsException:
			pass
		except exceptions.need2FAException:
			pass
		except exceptions.loginFailedException:
			pass
