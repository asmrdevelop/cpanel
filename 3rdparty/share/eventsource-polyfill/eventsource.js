;(function (global) {

if ("EventSource" in global) return;

var reTrim = /^(\s|\u00A0)+|(\s|\u00A0)+$/g;

var HTTPStatus = {
  OK: 200,
};

var EventSourceReadyState = {
  CONNECTING: 0,
  OPEN: 1,
  CLOSED: 2,
};

var XHRReadyState = {
  UNSENT: 0,
  OPENED: 1,
  HEADERS_RECEIVED: 2,
  LOADING: 3,
  DONE: 4,
};

var EventSource = function (url) {
  var eventsource = this,  
      interval = 500, // polling interval  
      lastEventId = null,
      cache = '';

  if (!url || typeof url != 'string') {
    throw new SyntaxError('Not enough arguments');
  }

  this.URL = url; // so older code will not break
  this.url = url; // to match standard
  this.readyState = EventSourceReadyState.CONNECTING;
  this._pollTimer = null;
  this._xhr = null;

  function isClosed(eventsource) {
    return eventsource.readyState === EventSourceReadyState.CLOSED;
  };

  function pollAgain(interval) {
    eventsource._pollTimer = setTimeout(function () {
      poll.call(eventsource);
    }, interval);
  }
  
  function poll() {
    try { // force hiding of the error message... insane?
      if (isClosed(eventsource)) return;

      // NOTE: IE7 and upwards support
      var xhr = new XMLHttpRequest();
      xhr.open('POST', eventsource.url, true);
      xhr.setRequestHeader('Accept', 'text/event-stream');
      xhr.setRequestHeader('Cache-Control', 'no-cache');
      // we must make use of this on the server side if we're working with Android - because they don't trigger
      // readychange until the server connection is closed
      xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');

      if (lastEventId != null) xhr.setRequestHeader('Last-Event-ID', lastEventId);
      cache = '';

      var timeout = 50000;

      // These have to survive outside of the change event
      // since an event may be spread across multiple xhr
      // change events.
      var data = [];
      var eventType = 'message';
      var retry;
      var buffer = new TextBuffer();

      xhr.onreadystatechange = function () {
        if (this.readyState == XHRReadyState.LOADING || (this.readyState == XHRReadyState.DONE && this.status == HTTPStatus.OK)) {
          // on success
          if (eventsource.readyState == EventSourceReadyState.CONNECTING) {
            eventsource.readyState = EventSourceReadyState.OPEN;
            eventsource.dispatchEvent('open', { type: 'open' });
          }

          var responseText = '';
          try {
            responseText = this.responseText || '';
          } catch (e) {}
        
          // process this.responseText
          var newText = responseText.substr(cache.length);
          buffer.append(newText);

          cache = responseText;
        
          // TODO handle 'event' (for buffer name), retry
          while (buffer.hasLine()) {
            var line = buffer.popLine().replace(reTrim, '');

            if (line.indexOf('event') == 0) {
              eventType = line.replace(/^event:?\s*/, '');
            } else if (line.indexOf('retry') == 0) {
              retry = parseInt(line.replace(/^retry:?\s*/, ''));
              if(!isNaN(retry)) { interval = retry; }
            } else if (line.indexOf('data') == 0) {
              data.push(line.replace(/^data:?\s*/, ''));
            } else if (line.indexOf('id:') == 0) {
              lastEventId = line.replace(/^id:?\s*/, '');
            } else if (line.indexOf('id') == 0) { // this resets the id
              lastEventId = null;
            } else if (line == '') {
              if (data.length) {
                if (!isClosed(eventsource)) {
                  var event = new MessageEvent(data.join('\n'), eventsource.url, lastEventId);
                  eventsource.dispatchEvent(eventType, event);
                }
                data = [];
                eventType = 'message';
              }
            }
          }

          if (this.readyState == XHRReadyState.DONE && !isClosed(eventsource)) pollAgain(interval);
          // don't need to poll again, because we're long-loading
        } else if (!isClosed(eventsource)) {
          if (this.readyState == XHRReadyState.DONE) { // and some other status
            // dispatch error
            eventsource.readyState = EventSourceReadyState.CONNECTING;

            if (eventsource._aborted_via_timeout) {
              delete eventsource._aborted_via_timeout;
              pollAgain(interval);
            } else if(!eventsource._aborted_by_application) {
              eventsource.dispatchEvent('error', { type: 'error' });
              pollAgain(interval);
            }
          } else if (this.readyState == XHRReadyState.UNSENT) { // likely aborted
            pollAgain(interval);
          }
        }
      };
    
      xhr.send();

      eventsource._timeoutTimer = setTimeout(function () {
        eventsource._aborted_via_timeout = true;
        xhr.abort();
      }, timeout);
      
      eventsource._xhr = xhr;
    
    } catch (e) { // in an attempt to silence the errors
      eventsource.dispatchEvent('error', { type: 'error', data: e.message }); // ???
    } 
  };
  
  poll(); // init now
};

EventSource.prototype = {
  close: function () {
    // closes the connection - disabling the polling
    this.readyState = EventSourceReadyState.CLOSED;
    if (this._pollTimer) {
      clearTimeout(this._pollTimer);
      this._pollTimer = null;
    }
    if (this._timeoutTimer) {
      clearTimeout(this._timeoutTimer);
      this._timeoutTimer = null;
    }
    this._aborted_by_application = true;
    this._xhr.abort();
  },
  dispatchEvent: function (type, event) {
    event.target = this;

    var handlers = this['_' + type + 'Handlers'];
    if (handlers) {
      for (var i = 0; i < handlers.length; i++) {
        handlers[i].call(this, event);
      }
    }

    if (this['on' + type]) {
      this['on' + type].call(this, event);
    }
  },
  addEventListener: function (type, handler) {
    if (!this['_' + type + 'Handlers']) {
      this['_' + type + 'Handlers'] = [];
    }
    
    this['_' + type + 'Handlers'].push(handler);
  },
  removeEventListener: function (type, handler) {
    var handlers = this['_' + type + 'Handlers'];
    if (!handlers) {
      return;
    }
    for (var i = handlers.length - 1; i >= 0; --i) {
      if (handlers[i] === handler) {
        handlers.splice(i, 1);
        break;
      }
    }
  },
  onerror: null,
  onmessage: null,
  onopen: null,
  readyState: XHRReadyState.CONNECTING,
  url: ''
};

var MessageEvent = function (data, origin, lastEventId) {
  this.data = data;
  this.origin = origin;
  this.lastEventId = lastEventId || '';
};

MessageEvent.prototype = {
  data: null,
  type: 'message',
  lastEventId: '',
  origin: ''
};

var TextBuffer = function(initial) {
  this.buffer = initial || '';
};

TextBuffer.prototype = {
  append: function(text) {
    this.buffer += text;
  },
  hasLine: function() {
    return /\n/.test(this.buffer);
  },
  popLine: function() {
    var length = this.buffer.length;

    if (!length) {
      return '';
    }

    var line = '';
    var pos = 0;

    while(pos < this.buffer.length) {
      if (this.buffer[pos] === '\n') {
        line = this.buffer.slice(0, pos + 1);
        if (length > pos + 1) {
          this.buffer = this.buffer.slice(pos + 1);
        } else {
          this.buffer = '';
        }
        return line;
      };
      pos++;
    }

    return '';
  }
}

if ('module' in global) module.exports = EventSource;
global.EventSource = EventSource;
 
})(this);
