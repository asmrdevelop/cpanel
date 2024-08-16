/**
 * Dual licensed under the Apache License 2.0 and the MIT license.
 * $Revision$ $Date$
 */

YAHOO.namespace('util.Cometd');

YAHOO.util.Cometd = function(name)
{
    // Remap cometd JSON functions to jquery JSON functions
    org.cometd.JSON.toJSON = YAHOO.lang.JSON.stringify;
    org.cometd.JSON.fromJSON = YAHOO.lang.JSON.parse;

    // The default cometd instance
    var cometd = new org.cometd.Cometd(name);

    // Remap toolkit-specific transport calls
    function LongPollingTransport()
    {
        var _super = new org.cometd.LongPollingTransport();
        var that = org.cometd.Transport.derive(_super);

        that.xhrSend = function(packet)
        {
            YAHOO.util.Connect.setDefaultPostHeader('application/json;charset=UTF-8');

            var thisRequest = YAHOO.util.Connect.asyncRequest(
                'POST',
                packet.url,
                {
                    success: function(o) {
                        packet.onSuccess(o.responseText);
                    },
                    error: function(o)
                    {
                        packet.onError(o.status,o.statusText);
                    }
                },
                packet.body
            );
            thisRequest.abort = function () { YAHOO.util.Connect.abort(this); };
            return thisRequest;
        };

        return that;
    };

    function CallbackPollingTransport()
    {
        var _super = new org.cometd.CallbackPollingTransport();
        var that = org.cometd.Transport.derive(_super);

        that.jsonpSend = function(packet)
        {
            var thisRequest = YAHOO.util.Connect.asyncRequest(
                'GET',
                packet.url + 'data=' + encodeURIComponent(packet.body),
                {
                    success: function(o) {
                        packet.onSuccess(o.responseText);
                    },
                    error: function(o)
                    {
                        packet.onError(o.status,o.statusText);
                    }
                }
            );
            thisRequest.abort = function () { YAHOO.util.Connect.abort(this); };
            return thisRequest;
        };

        return that;
    };

    if (window.WebSocket && 0) // disabled due to being broken in some versions of chrome
    {
        cometd.registerTransport('websocket', new org.cometd.WebSocketTransport());
    }
    cometd.registerTransport('long-polling', new LongPollingTransport());
    cometd.registerTransport('callback-polling', new CallbackPollingTransport());

    return cometd;
};


YAHOO.util.Cometd.cometd = new YAHOO.util.Cometd();
