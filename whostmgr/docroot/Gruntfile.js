/* global module: false */

module.exports = function(grunt) {

    grunt.loadNpmTasks("grunt-cpanel-optimizer");
    grunt.loadNpmTasks("grunt-cpanel-karma");

    grunt.registerTask("default", [
        "optimize"
    ]);
};
