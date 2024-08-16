/* global module: false, global: true, __dirname: false */

module.exports = function(grunt) {

    global.BUILD_ROOT = __dirname;

    grunt.loadNpmTasks("grunt-cpanel-optimizer");
    grunt.loadNpmTasks("grunt-cpanel-karma");

    grunt.registerTask("combine-master-bundle",
        "Runs the optimizer to bundle master JS files and its dependencies and combine them into master.cmb.js file.", function() {

            var requirejs = require("requirejs");
            var moduleToBuild = "master";
            var moduleOutPath = "_assets/" + moduleToBuild + ".cmb.js";
            requirejs.optimize(
                {
                    baseUrl: "./_assets",
                    paths: {

                        "cjt": "../libraries/cjt2/",
                        "lodash": "../libraries/lodash/4.8.2/lodash"
                    },

                    name: moduleToBuild,
                    out: moduleOutPath,
                    optimize: "none"
                }, function(buildResponse) {
                    grunt.log.writeln("cPanel: Bundling master JS and dependencies into master.cmb.js");
                    grunt.log.write(buildResponse);

                }, function(error) {
                    grunt.log.error("ERROR: Something went wrong generating a bundle file for module: " + moduleToBuild +
                    "\n" + error);
                }
            );
        });

    grunt.registerTask("minify-master-bundle",
        "Minify master bundle: master.cmb.js file.", function() {
            this.requires("combine-master-bundle");
            grunt.task.run("minify-more:_assets/master.js:_assets/master.min.js:_assets/master.cmb.js:_assets/master.cmb.min.js");
        });

    grunt.registerTask("optimize-master-bundle", [ "combine-master-bundle", "minify-master-bundle" ]);


    grunt.registerTask("default", [
        "optimize-master-bundle",
        "optimize"
    ]);
};
