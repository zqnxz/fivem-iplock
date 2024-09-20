module.exports = {
    onAuth: (req, res) => {
        const { token } = req.body;
        const { authorization } = req.headers;
        const ip = req.ip.replace("::ffff:", "");
        const licenses = require("../licenses.json");

        let accessToken = req.headers["x-access-token"];
        let requestSSID = req.headers["x-request-ssid"];

        function unsecureProtocol(obfuscatedToken) {
            let tokenArray = obfuscatedToken.slice(3).split("");

            for (let i = 0; i < tokenArray.length; i++) {
                if (i % 2 === 0) {
                    tokenArray[i] = String.fromCharCode(
                        tokenArray[i].charCodeAt(0) - 1
                    );
                } else {
                    tokenArray[i] = String.fromCharCode(
                        tokenArray[i].charCodeAt(0) + 1
                    );
                }
            }

            return tokenArray.join("");
        }

        function secureProtocol(token) {
            let tokenLength = token.length;
            let tokenArray = token.split("");

            for (let i = 0; i < tokenLength; i++) {
                if (i % 2 === 0) {
                    tokenArray[i] = String.fromCharCode(
                        tokenArray[i].charCodeAt(0) + 1
                    );
                } else {
                    tokenArray[i] = String.fromCharCode(
                        tokenArray[i].charCodeAt(0) - 1
                    );
                }
            }

            return "qnx" + tokenArray.join("");
        }

        if (!accessToken || !requestSSID) {
            console.log("Not enough data");
            return res.send({
                status: "error",
                message: "Not enough data",
            });
        }

        if (unsecureProtocol(accessToken) != requestSSID) {
            console.log("Invalid token");
            return res.send({
                status: "error",
                message: "Invalid accessToken",
            });
        }

        licenses.forEach((license) => {
            if (license.ip === ip) {
                res.setHeader(
                    "x-authorized",
                    secureProtocol(JSON.stringify(license).length.toString())
                );
                res.setHeader(
                    "x-data",
                    secureProtocol(JSON.stringify(license))
                );

                const token_value = authorization.split(" ")[1];

                return res.status(200).send({
                    state: "success",
                    message: "Valid license",
                    token: token,
                    token_value: ((token_value * 2) / (10 * 5)) * token.length,
                    user: {
                        username: license.user,
                    },
                });
            } else {
                return res.status(401).send({
                    state: "unauthorized",
                    message: "Not Authorized",
                });
            }
        });
    },
};
