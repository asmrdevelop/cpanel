/**
 * @license Copyright (c) 2003-2013, CKSource - Frederico Knabben. All rights reserved.
 * For licensing, see LICENSE.html or http://ckeditor.com/license
 */

/**
 * @fileOverview Save plugin.
 */

(function() {
    var saveCmd = { modes:{wysiwyg:1,source:1 },
        readOnly: 1,

        exec: function( editor ) {
            var $form = editor.element.$.form;

            if ( $form ) {
                try {
                    editor.fire("customSave");
                } catch ( e ) {
                    console.log("error occurred while saving");
                }
            }
        }
    };

    var pluginName = 'cpanelsave';

    // Register a plugin named "cpanelsave".
    CKEDITOR.plugins.add( pluginName, {
        lang: 'af,ar,bg,bn,bs,ca,cs,cy,da,de,el,en,en-au,en-ca,en-gb,eo,es,et,eu,fa,fi,fo,fr,fr-ca,gl,gu,he,hi,hr,hu,is,it,ja,ka,km,ko,ku,lt,lv,mk,mn,ms,nb,nl,no,pl,pt,pt-br,ro,ru,si,sk,sl,sq,sr,sr-latn,sv,th,tr,ug,uk,vi,zh,zh-cn', // %REMOVE_LINE_CORE%
        icons: 'cpanelsave', // %REMOVE_LINE_CORE%
        init: function( editor ) {

            // Save plugin is for replace mode only.
            if ( editor.elementMode != CKEDITOR.ELEMENT_MODE_REPLACE )
                return;

            var command = editor.addCommand( pluginName, saveCmd );
            //command.modes = { wysiwyg: !!( editor.element.$.form ) };

            editor.ui.addButton && editor.ui.addButton( 'CpanelSave', {
                label: editor.lang.cpanelsave.toolbar,
                command: pluginName,
                toolbar: 'document,10'
            });
        }
    });
})();
