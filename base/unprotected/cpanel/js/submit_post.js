/*
# base/unprotected/js/submit_post.js               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * ----------------------------------------------------------------------
 * SubmitPost.js - Module to send the browser to a URL via POST.
 *
 * SYNOPSIS:
 *
 *  SubmitPost.submit( 'https://some.host/wherever', {
 *      foo => 123,
 *      bar => "abc",
 *      baz => [ 234, "qwe" ],
 *  } );
 *
 * The above has the same effect as setting “location.href” but sends a
 * POST instead of a GET. The given object’s contents are encoded as a
 * standard HTML form submission.
 * ----------------------------------------------------------------------
*/

( function(context) {
    "use strict";

    var DOC = context.document;

    function _wrongType(name, value) {
        throw new Error("“" + name + "” must be a string, number, or array, not " + value);
    }

    var scalarTypeIsOk = {
        number: true,
        string: true,
    };

    function submit(url, args) {
        var myform = DOC.createElement("form");
        myform.method = "POST";
        myform.action = url;

        myform.style.display = "none";

        Object.keys(args).forEach( function(name) {
            var values;

            if ("object" === typeof args[name]) {
                if (args[name] instanceof Array) {
                    values = args[name];
                } else {
                    _wrongType(name, args[name]);
                }
            } else if (scalarTypeIsOk[ typeof args[name] ]) {
                values = [ args[name] ];
            } else {
                _wrongType(name, args[name]);
            }

            values.forEach( function(val) {
                var myvar = DOC.createElement("input");
                myvar.type = "hidden";
                myvar.name = name;
                myvar.value = val;

                myform.appendChild(myvar);
            } );
        } );

        DOC.documentElement.appendChild(myform);

        myform.submit();

        DOC.documentElement.removeChild(myform);
    }

    context.SubmitPost = { submit: submit };
})(window);
