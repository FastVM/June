export default {
  mode: 'production',
  output: {
    clean: true,
    filename: 'lua.js'
  },
  target: 'node',
  module: {
    rules: [
      {
        test: /\.(?:js|mjs|cjs)$/,
        use: {
          loader: "babel-loader",
        },
      },
    ],
  },
  stats: {
    warnings: false,
  }
};
