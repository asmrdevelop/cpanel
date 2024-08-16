/*
# ckeditor_plugins/cpanelpreview/plugin.js
#
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global CKEDITOR: false */

/**
 * @fileOverview Preview plugin.
 */

(function() {

    "use strict";

    var previewCmd = { modes: { wysiwyg: 1, source: 1 },
        readOnly: 1,

        exec: function( editor ) {
            var $form = editor.element.$.form;

            if ( $form ) {
                try {
                    editor.fire("customPreview");
                } catch ( e ) {
                    console.log("error while loading preview", e); // eslint-disable-line no-console
                }
            }
        }
    };

    var pluginName = "cpanelpreview";

    // Register a plugin named "cpanelpreview".
    CKEDITOR.plugins.add( pluginName, {
        icons: "cpanelpreview", // %REMOVE_LINE_CORE%
        init: function( editor ) {

            // Save plugin is for replace mode only.
            if ( editor.elementMode !== CKEDITOR.ELEMENT_MODE_REPLACE ) {
                return;
            }

            editor.addCommand( pluginName, previewCmd );

            // command.modes = { wysiwyg: !!( editor.element.$.form ) };

            var lang = CKEDITOR.lang.detect();

            editor.ui.addButton && editor.ui.addButton( "CpanelPreview", {
                label: CKEDITOR.lang[lang] ? CKEDITOR.lang[lang].preview.preview : "Preview",
                command: pluginName,
                icon: "preview",
                toolbar: "document,10"
            });
        }
    });
})();
