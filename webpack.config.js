import path from 'path';

export default {
  entry: "./src/index.js",
  mode: "production",
  module: {
    rules: [
      // {
      //   exclude: /(node_modules)/,
      //   test: /\.(js|jsx)$/i,
      //   loader: "babel-loader"
      // }
    ]
  },
  target: 'node',
  output: {
    path: path.resolve("dist")
  },
  optimization: {
    minimize: true,
    usedExports: true,
  },
  plugins: []
};
