/*
# cjt/directives/terminal.js                      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* ----------------------------------------------------------------------
INSTRUCTIONS FOR THIS DIRECTIVE:

You must independently load xterm.js’s CSS file, e.g.:

    /libraries/xtermjs/xterm.min.css
    /frontend/<theme-name>/libraries/xtermjs/xterm.min.css

The following goes in your AngularJS template:

    <cp-terminal></cp-terminal>

This reports alerts to the “myalerts” alert group (cf. the cp-alert-list
directive).

For now there’s not much flexibility because it’s only being used in
contexts where the directive basically *is* the application.
---------------------------------------------------------------------- */

/* global define: false */

define(
    [
        "lodash",
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/uaDetect",
        "cjt/util/query",
        "cjt/io/websocket",
        "cjt/io/appstream",
        "xterm",
        "xterm/addons/fit/fit",
        "cjt/modules",
        "cjt/services/alertService",
        "cjt/directives/alert",
        "cjt/directives/alertList",
        "cjt/services/onBeforeUnload",
        "uiBootstrap",
    ],
    function(_, angular, CJT, LOCALE, UA, QUERY, WEBSOCKET, APPSTREAM, Terminal, Fit) {
        "use strict";

        Terminal.applyAddon(Fit);

        var module = angular.module("cjt2.directives.terminal", []);
        var TEMPLATE_PATH = "libraries/cjt2/directives/terminal.phtml";

        var NBSP = "\u00a0";

        // A resize is handled by cpsrvd itself rather than the shell,
        // so we send this information in an AppStream control message.
        function _sendResize(ws, term) {
            var rows = term.rows;
            var cols = term.cols;

            var msg = "resize:" + rows + "," + cols;

            ws.send( APPSTREAM.encodeControlPayload(msg) );
        }

        var shellUrl = WEBSOCKET.getUrlBase() + "/websocket/Shell";

        module.directive("cpTerminal", [ "alertService", "$log", "onBeforeUnload",
            function(alertService, $log, onBeforeUnload) {
                function _reportError(str) {
                    alertService.add({
                        type: "danger",
                        message: str,
                        closeable: true,
                        autoClose: false,
                        replace: false,
                        group: "myalerts"
                    });
                }

                return {
                    restrict: "E",
                    replace: true,
                    templateUrl: CJT.config.debug ? CJT.buildFullPath(TEMPLATE_PATH) : TEMPLATE_PATH,
                    controller: ["$scope", "$element", function($scope, $element) {
                        var terminalIsOpen;

                        var term = new Terminal( {
                            macOptionIsMeta: UA.isMacintosh(),

                            // These are defaults that we update
                            // via fit() prior to opening the WebSocket
                            // connection. We send the resulting dimensions
                            // as query parameters; this way the pty
                            // on the backend has the correct dimensions
                            // from the get-go.
                            cols: $scope._DEFAULT_COLS,
                            rows: $scope._DEFAULT_ROWS,
                        } );

                        // Use a closure rather than bind() here so that it’s always
                        // the same function regardless of the ws instance.
                        function _sendData(d) {
                            $scope._ws.send( APPSTREAM.encodeDataPayload(d) );
                        }
                        term.on("data", _sendData);

                        // It’s possible to resize the window between the
                        // time when we send off the WebSocket handshake and
                        // when we get the response. When that happens we need
                        // to mark the need to send off a window resize once
                        // the connection is open.
                        var pendingResize;

                        function fitAndSendGeometry() {
                            term.fit();

                            var ws = $scope._ws;
                            if (ws) {
                                if (ws.readyState === WebSocket.OPEN) {
                                    _sendResize(ws, term);
                                } else {
                                    pendingResize = true;
                                }
                            }
                        }

                        window.addEventListener("resize", fitAndSendGeometry);
                        if (CJT.isWhm()) {
                            window.addEventListener("toggle-navigation", fitAndSendGeometry);
                            window.addEventListener("toggle-navigation", fitAndSendGeometry);
                        }

                        term.on( "title", function _setTitle(title) {
                            $scope.title = title || NBSP;
                            $scope.$apply();
                        } );

                        // ------------------------------------------------
                        function _wsOnError(e) {
                            $log.error(e.toString());
                        }
                        function _wsOnOpen(e) {
                            $scope.opening = false;
                            $scope.$apply();

                            if (pendingResize) {
                                _sendResize( e.target, term );
                                pendingResize = false;
                            }
                        }
                        function _wsOnFirstMessage(e) {
                            var ws = e.target;
                            ws.removeEventListener("message", _wsOnFirstMessage);
                            $scope.loading = false;
                            $scope.$apply();

                            term.textarea.disabled = false;
                            term.textarea.focus();
                        }
                        function _wsOnClose(evt) {
                            $scope._ws = null;

                            if (!onBeforeUnload.windowIsUnloading() && (evt.code !== WEBSOCKET.STATUS.SUCCESS)) {
                                var errStr;
                                if ($scope.opening && (evt.code === WEBSOCKET.STATUS.ABORTED)) {
                                    errStr = LOCALE.maketext("The [asis,WebSocket] handshake failed at [local_datetime,_1,time_format_medium].", new Date());
                                } else {
                                    var why, errDetail;
                                    try {
                                        why = JSON.parse( evt.reason );
                                        if (why.got_signal) {
                                            errDetail = "SIG" + why.result;
                                            if (why.dumped_core) {
                                                errDetail += ", +core";
                                            }
                                        } else {
                                            $scope.exitCode = why.result;
                                        }
                                    } catch (err) {

                                        // Don’t warn if the server went away
                                        // suddenly.
                                        if (evt.reason) {
                                            $log.warn("JSON parse: " + err);
                                        }

                                        errDetail = WEBSOCKET.getErrorString(evt);
                                    }

                                    if (errDetail) {
                                        errStr = LOCALE.maketext("The connection to the server ended in failure at [local_datetime,_1,time_format_medium]. ([_2])", new Date(), errDetail);
                                    }
                                }

                                if (errStr) {
                                    _reportError(errStr);
                                }
                            }

                            $scope.closed = true;
                            $scope.opening = false;
                            $scope.loading = false;
                            $scope.$apply();

                            if (term.textarea) {
                                term.textarea.disabled = true;
                            }
                        }

                        // ------------------------------------------------

                        // Edge & IE11 lack TextDecoder support,
                        // so we have to do it manually.
                        // We could send text messages rather than binary,
                        // but it’ll be nice to be able to add ZMODEM support
                        // later on, and for that we’ll need binary.
                        function _setupBinaryParser(ws, term) {
                            var blobQueue = [];

                            var fileReader = new FileReader();

                            // NB: As of March 2018, our PhantomJS version
                            // doesn’t recognize addEventListener on
                            // FileReader instances.
                            fileReader.onload = function(e) {
                                term.write( e.target.result );

                                if (blobQueue.length) {
                                    e.target.readAsText( blobQueue.shift() );
                                }
                            };
                            fileReader.onerror = function(e) {
                                _reportError("UTF-8 decode error: " + e.target.error.toString());
                            };

                            $scope._wsOnMessage = function(evt) {
                                if (fileReader.readyState === FileReader.LOADING) {
                                    blobQueue.push(evt.data);
                                } else {
                                    fileReader.readAsText(evt.data);
                                }
                            };
                            ws.addEventListener("message", $scope._wsOnMessage);
                        }

                        // ------------------------------------------------

                        function _connect() {
                            if ($scope._ws) {
                                throw new Error("WebSocket already open!");
                            }

                            $scope.exitCode = null;

                            if (!terminalIsOpen) {
                                var parentNode = $element.find(".terminal-xterm").get(0);
                                if (!parentNode) {
                                    throw new Error("_connect() with no parent node!");
                                }

                                term.open( parentNode, true );
                                term.textarea.disabled = true;
                                term.fit();
                                terminalIsOpen = true;
                            }

                            var queryStr = QUERY.make_query_string( {
                                rows: term.rows,
                                cols: term.cols,
                            } );
                            var fullUrl = shellUrl + "?" + queryStr;

                            var WSConstructor = $scope._WebSocket;
                            $scope._ws = new WSConstructor(fullUrl);

                            $scope.opening = true;
                            $scope.loading = true;
                            $scope.closed = false;

                            var ws = $scope._ws;
                            ws.addEventListener( "error", _wsOnError );

                            ws.addEventListener( "open", _wsOnOpen );

                            // We wait until the first message to display
                            // the terminal because we want there to be a
                            // “waiting for terminal …” state to report.
                            ws.addEventListener( "message", _wsOnFirstMessage );

                            _setupBinaryParser( ws, term );

                            ws.addEventListener( "close", _wsOnClose );
                        }

                        _.assign(
                            $scope,
                            {
                                title: NBSP,

                                connect: _connect,

                                // while opening the WebSocket connection:
                                opening: true,

                                // while we’ve not received a message yet
                                // (implies “opening”)
                                loading: true,

                                // after a connection closes
                                closed: false,

                                exitCode: null,

                                // Strings
                                openingString: LOCALE.maketext("Opening a connection …"),
                                waitingString: LOCALE.maketext("Waiting for the terminal …"),
                                reconnectString: LOCALE.maketext("Reconnect"),
                                exitCodeString: LOCALE.maketext("Exit Code"),

                                // ----------------------------------------
                                // Testing interface
                                _alertService: alertService,
                                _DEFAULT_COLS: 80,
                                _DEFAULT_ROWS: 24,
                                _window: window,
                                _WebSocket: $scope._WebSocket || window.WebSocket,
                                _ws: null,
                                _wsOnError: _wsOnError,
                                _wsOnOpen: _wsOnOpen,
                                _wsOnFirstMessage: _wsOnFirstMessage,
                                _wsOnMessage: null,
                                _wsOnClose: _wsOnClose,
                            }
                        );

                        _connect();
                    } ],
                };
            }
        ] );
    }
);
