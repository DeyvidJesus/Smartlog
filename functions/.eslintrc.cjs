module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    // O runtime é Node 24; 2018 é o padrão antigo do template e quebra o parse
    // de optional chaining (?.) e nullish coalescing (??).
    "ecmaVersion": 2022,
    // A função usa import/export (package.json tem "type": "module"), para
    // reaproveitar contexto.js e relevancia.js sem reescrever em CommonJS.
    "sourceType": "module",
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
    // O prompt do sistema é um template literal: quebrar as linhas para
    // caber em 80 colunas inseriria \n e alteraria o prompt enviado.
    "max-len": ["error", {"code": 80, "ignoreTemplateLiterals": true}],
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
};
