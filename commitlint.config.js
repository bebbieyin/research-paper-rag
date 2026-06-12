module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "subject-case": [0],
    "body-max-line-length": [2, "always", 200],
    "type-enum": [
      2,
      "always",
      [
        "feat",     // New feature
        "fix",      // Bug fix
        "chore",    // Maintenance
        "refactor", // Restructure, no behavior change
        "test",     // Tests
        "revert",   // Revert a previous commit
      ],
    ],
    "scope-enum": [0],
    "scope-empty": [0],
  },
};
