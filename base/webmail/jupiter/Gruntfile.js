/*
# cpanel - base/webmail/jupiter/Gruntfile.js       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global module: false */

module.exports = function(grunt) {

    grunt.loadNpmTasks("grunt-cpanel-optimizer");
    grunt.loadNpmTasks("grunt-cpanel-karma");

    grunt.registerTask("default", [
        "optimize",
    ]);
};
