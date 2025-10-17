const path = require('path');
const HtmlWebpackPlugin = require('html-webpack-plugin');

module.exports = {
  entry: './src/main.ts',
  resolve: { extensions: ['.ts', '.js'] },
  module: {
    rules: [
      { test: /\.ts$/, loader: 'ts-loader', exclude: /node_modules/ }
    ]
  },
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'bundle.js',
    clean: true
  },
  devServer: {
    port: 4200,
    historyApiFallback: true,
    proxy: {
      '/api': 'http://localhost:7071'
    }
  },
  plugins: [
    new HtmlWebpackPlugin({ template: 'src/index.html' })
  ]
};
