function transform_inputs() {
    var inputs = document.getElementsByTagName("input");
    for (var i = 0; i < inputs.length; i++) {
        if (inputs[i].type == "text") {
            if (inputs[i].value.match(/^\s*(On|Off)\s*$/i)) {
                var thisval = inputs[i].value;
                var tname = inputs[i].name;
                var parentN = inputs[i].parentNode;
                parentN.removeChild(inputs[i]);

                // we used to do this with dom, but ie chokes

                var newhtml = '<input type="radio" ' + (thisval.match(/off/i) ? 'checked="checked"' : "") + ' name="' + tname + '" value="Off" />' +
                    "<span>Off</span>" +
                    '<input type="radio" ' + (thisval.match(/on/i) ? 'checked="checked"' : "") + ' name="' + tname + '" value="On" />' +
                    "<span>On</span>";
                parentN.innerHTML = newhtml;
            }
        }
    }
}

YAHOO.util.Event.addListener(window, "load", transform_inputs, this);
