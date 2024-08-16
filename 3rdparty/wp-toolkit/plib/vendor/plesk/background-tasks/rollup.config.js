import babel from 'rollup-plugin-babel'
import commonjs from 'rollup-plugin-commonjs'
import external from 'rollup-plugin-peer-deps-external'
import postcss from 'rollup-plugin-postcss'
import resolve from 'rollup-plugin-node-resolve'
import url from 'rollup-plugin-url'
import modify from 'rollup-plugin-modify';
import svgr from '@svgr/rollup'

import pkg from './package.json'

export default {
  input: 'frontend/index.js',
  output: [
    {
      file: pkg.main,
      format: 'cjs',
      sourcemap: true
    },
    {
      file: pkg.module,
      format: 'es',
      sourcemap: true
    }
  ],
  plugins: [
    external(),
    modify({
      find: '@\{cls-prefix\}',
      replace: 'background-tasks-',
    }),
    postcss({
      modules: false
    }),
    url(),
    svgr(),
    babel({
      exclude: 'node_modules/**',
      plugins: [ 'external-helpers' ]
    }),
    resolve(),
    commonjs()
  ],
  external: Object.keys(pkg.devDependencies),
}
