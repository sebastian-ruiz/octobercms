'use strict';

module.exports = function (grunt) {
    // load all grunt tasks
    grunt.loadNpmTasks('grunt-subgrunt');

    grunt.initConfig({
        subgrunt: {
            theme: {
                options: {
                    // Target-specific options
                },
                projects: {
                    'themes/bs':  ['concat', 'uglify', 'less'],
                    'themes/lo':  ['concat', 'uglify', 'less']
                }
            },
            bbrs: {
                options: {
                    // Target-specific options
                },
                projects: {
                    'plugins/bs/bbrs':  ['sass']
                }
            }
        }
    });

    grunt.registerTask('default', 'subgrunt');
};


