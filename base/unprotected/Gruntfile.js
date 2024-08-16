/* global module: false, require: false */

module.exports = function(grunt) {

    grunt.loadNpmTasks("grunt-cpanel-optimizer");
    grunt.loadNpmTasks("grunt-cpanel-karma");
    grunt.loadNpmTasks("grunt-contrib-watch");

    grunt.initConfig({
        watch: {
            karma: {
                files: ["cpanel/**/*.js", "!**/*.min.js", "!**/*.cmb.js"],
                tasks: ["optimize", "bell"]
            },
            make: {
                files: ["cpanel/**/*.less"],
                tasks: ["make", "bell"]
            }
        }
    });

    grunt.registerTask("make", function() {
        var done = this.async();
        var exec = require("child_process").exec;

        exec("make", function(error, stdout, stderr) {
            if(error) {
                grunt.log.error(stderr);
            }
            else {
                grunt.log.writeln(stdout);
            }

            done();
        });
    });

    grunt.registerTask("bell", function() {
        console.log("\u0007");
    });

    grunt.registerTask("default", [
        "optimize"
    ]);
};