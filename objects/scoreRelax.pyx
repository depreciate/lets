import time

import pp
from common.constants import gameModes, mods
from objects import beatmap
from common import generalUtils
from common.constants import gameModes
from common.log import logUtils as log
from common.ripple import userUtils
from constants import rankedStatuses
from common.ripple import scoreUtils
from objects import glob
from pp import relaxoppai
from pp import rippoppai
from pp import wifipiano2
from pp import cicciobello


class score:
	PP_CALCULATORS = {
		gameModes.STD: relaxoppai.oppai,
		gameModes.TAIKO: rippoppai.oppai,
		gameModes.CTB: cicciobello.Cicciobello,
		gameModes.MANIA: wifipiano2.piano
	}
	__slots__ = ["scoreID", "playerName", "score", "maxCombo", "c50", "c100", "c300", "cMiss", "cKatu", "cGeki",
				 "fullCombo", "mods", "playerUserID","rank","date", "hasReplay", "fileMd5", "passed", "playDateTime",
				 "gameMode", "completed", "accuracy", "pp", "display_pp", "oldPersonalBest", "rankedScoreIncrease", "personalOldBestScore",
				 "_playTime", "_fullPlayTime", "quit", "failed"]
	def __init__(self, scoreID = None, rank = None, setData = True):
		"""
		Initialize a (empty) score object.

		scoreID -- score ID, used to get score data from db. Optional.
		rank -- score rank. Optional
		setData -- if True, set score data from db using scoreID. Optional.
		"""
		self.scoreID = 0
		self.playerName = "nospe"
		self.score = 0
		self.maxCombo = 0
		self.c50 = 0
		self.c100 = 0
		self.c300 = 0
		self.cMiss = 0
		self.cKatu = 0
		self.cGeki = 0
		self.fullCombo = False
		self.mods = 0
		self.playerUserID = 0
		self.rank = rank
		self.date = 0
		self.hasReplay = 0

		self.fileMd5 = None
		self.passed = False
		self.playDateTime = 0
		self.gameMode = 0
		self.completed = 0

		self.accuracy = 0.00

		self.pp = 0.00
		self.display_pp = 0.00

		self.oldPersonalBest = 0
		self.rankedScoreIncrease = 0
		self.personalOldBestScore = None

		self._playTime = None
		self._fullPlayTime = None
		self.quit = None
		self.failed = None


		if scoreID is not None and setData:
			self.setDataFromDB(scoreID, rank)
	def _adjustedSeconds(self, x):
		if (self.mods & mods.DOUBLETIME) > 0:
			return x // 1.5
		elif (self.mods & mods.HALFTIME) > 0:
			return x // 0.75
		return x

	@property
	def fullPlayTime(self):
		return self._fullPlayTime

	@fullPlayTime.setter
	def fullPlayTime(self, value):
		value = max(0, value)
		self._fullPlayTime = self._adjustedSeconds(value)

	@property
	def playTime(self):
		return self._playTime

	@playTime.setter
	def playTime(self, value):
		value = max(0, value)
		value = self._adjustedSeconds(value)
		if self.fullPlayTime is not None and value > self.fullPlayTime * 1.33:
			value = 0
		self._playTime = value

	def calculateAccuracy(self):
		"""
		Calculate and set accuracy for that score
		"""
		if self.gameMode == 0:
			totalPoints = self.c50*50+self.c100*100+self.c300*300
			totalHits = self.c300+self.c100+self.c50+self.cMiss
			if totalHits == 0:
				self.accuracy = 1
			else:
				self.accuracy = totalPoints/(totalHits*300)
		elif self.gameMode == 1:
			totalPoints = (self.c100*50)+(self.c300*100)
			totalHits = self.cMiss+self.c100+self.c300
			if totalHits == 0:
				self.accuracy = 1
			else:
				self.accuracy = totalPoints / (totalHits * 100)
		elif self.gameMode == 2:
			fruits = self.c300+self.c100+self.c50
			totalFruits = fruits+self.cMiss+self.cKatu
			if totalFruits == 0:
				self.accuracy = 1
			else:
				self.accuracy = fruits / totalFruits
		elif self.gameMode == 3:
			totalPoints = self.c50*50+self.c100*100+self.cKatu*200+self.c300*300+self.cGeki*300
			totalHits = self.cMiss+self.c50+self.c100+self.c300+self.cGeki+self.cKatu
			self.accuracy = totalPoints / (totalHits * 300)
		else:
			self.accuracy = 0

	def setRank(self, rank):
		"""
		Force a score rank

		rank -- new score rank
		"""
		self.rank = rank
			
	def setDataFromDB(self, scoreID, rank = None):
		"""
		Set this object's score data from db
		Sets playerUserID too

		scoreID -- score ID
		rank -- rank in scoreboard. Optional.
		"""
		data = glob.db.fetch("SELECT scores_relax.*, users.username FROM scores_relax LEFT JOIN users ON users.id = scores_relax.userid WHERE scores_relax.id = %s LIMIT 1", [scoreID])
		if data is not None:
			self.setDataFromDict(data, rank)

	def setDataFromDict(self, data, rank = None):
		"""
		Set this object's score data from dictionary
		Doesn't set playerUserID

		data -- score dictionarty
		rank -- rank in scoreboard. Optional.
		"""
		self.scoreID = data["id"]
		if "username" in data:
			self.playerName = userUtils.getClan(data["userid"])
		else:
			self.playerName = userUtils.getUsername(data["userid"])
		self.playerUserID = data["userid"]
		self.score = data["score"]
		self.maxCombo = data["max_combo"]
		self.gameMode = data["play_mode"]
		self.c50 = data["50_count"]
		self.c100 = data["100_count"]
		self.c300 = data["300_count"]
		self.cMiss = data["misses_count"]
		self.cKatu = data["katus_count"]
		self.cGeki = data["gekis_count"]
		self.fullCombo = data["full_combo"] == 1
		self.mods = data["mods"]
		self.rank = rank if rank is not None else ""
		self.date = data["time"]
		self.fileMd5 = data["beatmap_md5"]
		self.completed = data["completed"]
		self.pp = data["pp"]
		self.display_pp = data["display_pp"]
		self.calculateAccuracy()

	def setDataFromScoreData(self, scoreData, quit_=None, failed=None):
		"""
		Set this object's score data from scoreData list (submit modular)

		scoreData -- scoreData list
		"""
		if len(scoreData) >= 16:
			self.fileMd5 = scoreData[0]
			self.playerName = scoreData[1].strip()
			self.c300 = int(scoreData[3])
			self.c100 = int(scoreData[4])
			self.c50 = int(scoreData[5])
			self.cGeki = int(scoreData[6])
			self.cKatu = int(scoreData[7])
			self.cMiss = int(scoreData[8])
			self.score = int(scoreData[9])
			self.maxCombo = int(scoreData[10])
			self.fullCombo = scoreData[11] == 'True'
			self.rank = scoreData[12]
			self.mods = int(scoreData[13])
			self.passed = scoreData[14] == 'True'
			self.gameMode = int(scoreData[15])
			self.playDateTime = int(time.time())
			self.calculateAccuracy()
			self.quit = quit_
			self.failed = failed

			self.setCompletedStatus()


	def getData(self, pp=True):
		b = beatmap.beatmap(self.fileMd5, 0)
		if b.rankedStatus == rankedStatuses.LOVED:
			return "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|1\n".format(
				self.scoreID,
				self.playerName,
				int(self.display_pp) if pp else self.score,
				self.maxCombo,
				self.c50,
				self.c100,
				self.c300,
				self.cMiss,
				self.cKatu,
				self.cGeki,
				self.fullCombo,
				self.mods,
				self.playerUserID,
				self.rank,
				self.date
			)
		else:
			return "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|1\n".format(
				self.scoreID,
				self.playerName,
				int(self.pp) if pp else self.score,
				self.maxCombo,
				self.c50,
				self.c100,
				self.c300,
				self.cMiss,
				self.cKatu,
				self.cGeki,
				self.fullCombo,
				self.mods,
				self.playerUserID,
				self.rank,
				self.date
			)

	def setCompletedStatus(self):
		"""
		Set this score completed status and rankedScoreIncrease
		"""
		try:
			#self.completed = 0
			
			b = beatmap.beatmap(self.fileMd5, 0)

			if self.passed and scoreUtils.isRankable(self.mods):
				userID = userUtils.getID(self.playerName)

				if b.rankedStatus == rankedStatuses.LOVED:
					personalBest = glob.db.fetch("SELECT id, display_pp, score FROM scores_relax WHERE userid = %s AND beatmap_md5 = %s AND play_mode = %s AND completed = 3 LIMIT 1", [userID, self.fileMd5, self.gameMode])
				else:
					personalBest = glob.db.fetch("SELECT id, pp, score FROM scores_relax WHERE userid = %s AND beatmap_md5 = %s AND play_mode = %s AND completed = 3 LIMIT 1", [userID, self.fileMd5, self.gameMode])

				if personalBest is None:
					self.completed = 3
					self.rankedScoreIncrease = self.score
					self.oldPersonalBest = 0
					self.personalOldBestScore = None
				else:
					self.personalOldBestScore = personalBest["id"]
					if b.rankedStatus in [rankedStatuses.RANKED, rankedStatuses.APPROVED, rankedStatuses.QUALIFIED]:
						self.calculatePP()
						if self.pp > personalBest["pp"]:
							self.completed = 3
							self.rankedScoreIncrease = self.score-personalBest["score"]
							self.oldPersonalBest = personalBest["id"]
						else:
							self.completed = 2
							self.rankedScoreIncrease = 0
							self.oldPersonalBest = 0
					elif b.rankedStatus == rankedStatuses.LOVED:
						self.calculatePP()
						if self.display_pp > personalBest["display_pp"]:
							self.completed = 3
							self.rankedScoreIncrease = self.score-personalBest["score"]
							self.oldPersonalBest = personalBest["id"]
						else:
							self.completed = 2
							self.rankedScoreIncrease = 0
							self.oldPersonalBest = 0
			elif self.quit:
				self.completed = -1
			elif self.failed:
				self.completed = -1

		finally:
			log.debug("Completed status: {}".format(self.completed))

	def saveScoreInDB(self):
		"""
		Save this score in DB (if passed and mods are valid)
		"""
		if self.completed >= 2:
			query = "INSERT INTO scores_relax (id, beatmap_md5, userid, score, max_combo, full_combo, mods, 300_count, 100_count, 50_count, katus_count, gekis_count, misses_count, `time`, play_mode, playtime, completed, accuracy, pp, display_pp, rank) VALUES (NULL, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);"
			self.scoreID = int(glob.db.execute(query, [self.fileMd5, userUtils.getID(self.playerName), self.score, self.maxCombo, int(self.fullCombo), self.mods, self.c300, self.c100, self.c50, self.cKatu, self.cGeki, self.cMiss, self.playDateTime, self.gameMode, self.playTime if self.playTime is not None and not self.passed else self.fullPlayTime, self.completed, self.accuracy * 100, self.pp, self.display_pp, self.rank]))
			scoreUtils.updateRankCounterRX(self.rank, self.gameMode, userUtils.getID(self.playerName))
			if self.oldPersonalBest != 0 and self.completed == 3:
				glob.db.execute("UPDATE scores_relax SET completed = 2 WHERE id = %s AND completed = 3 LIMIT 1", [self.oldPersonalBest])

			glob.redis.incr("ripple:total_submitted_scores", 1)
			glob.redis.incr("ripple:total_pp", int(self.pp))
		glob.redis.incr("ripple:total_plays", 1)

	def calculatePP(self, b = None):
		"""
		Calculate this score's pp value if completed == 3
		"""
		if b is None:
			b = beatmap.beatmap(self.fileMd5, 0)

		if b.rankedStatus in [rankedStatuses.RANKED, rankedStatuses.APPROVED, rankedStatuses.QUALIFIED] and b.rankedStatus != rankedStatuses.UNKNOWN \
		and scoreUtils.isRankable(self.mods) and self.gameMode in score.PP_CALCULATORS:
			calculator = score.PP_CALCULATORS[self.gameMode](b, self)
			self.pp = calculator.pp
			self.display_pp = calculator.pp
		else:
			calculator = score.PP_CALCULATORS[self.gameMode](b, self)
			self.pp = 0
			self.display_pp = calculator.pp
	
	def calculateDisplay(self, b = None):
		"""
		Calculate this score's pp value if completed oi== 3
		"""
		calculator = score.PP_CALCULATORS[self.gameMode](b, self)
		self.display_pp = calculator.pp
