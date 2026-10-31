const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    // sfdx-lwc-jest has no lightning/modal stub; the Owner Workspace entry form needs one.
    "^lightning/modal$": "<rootDir>/jest-mocks/lightning/modal/modal",
    // CSS-only module: the platform resolves it, Jest's resolver needs the file.
    "^c/vkfOwnerTokens$":
      "<rootDir>/force-app/main/default/lwc/vkfOwnerTokens/vkfOwnerTokens.css"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
