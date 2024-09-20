const router = require("express").Router();
const authController = require("../controllers/auth.controller");

router.post("/auth", authController.onAuth);

module.exports = router;
