const express = require("express");
const app = express();
const authRouter = require("./routes/auth.router");

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use("/api/v1/", authRouter);

app.listen(3000, () => {
    console.log("API started");
});
