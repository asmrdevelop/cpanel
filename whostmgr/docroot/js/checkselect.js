var checkselectenabled = 1;

var scrollMode = 2;

/* window */
var EU = YAHOO.util.Event;
var lastSelectTime = 0;
var checkarea = "checkarea";
var viewportHeight = 0;
var selectOvers = {};
var locCache = {};
var selectMode = 0;
var checkidgen = 0;
var moveEvent = 0;
var selector = checkarea;
var selectWindowRegion;
var selectStartScrollLeft;
var selectStartScrollTop;
var selectStartX;
var selectStartY;

var osmode = "unix";
var quirksmode = "Mozilla";
var osCheck = navigator.userAgent.toLowerCase();
var is_major = parseInt(navigator.appVersion);
var is_minor = parseFloat(navigator.appVersion);


if (osCheck.indexOf("win") != -1 || osCheck.indexOf("Windows") != -1) {
    osmode = "win32";
}
if (osCheck.indexOf("mac") != -1) {
    osmode = "mac";
}
if (navigator.appVersion.indexOf("MSIE") != -1) {
    quirksmode = "MSIE";
}
if (navigator.appVersion.indexOf("Safari") != -1) {
    quirksmode = "Safari";
    osmode = "mac";
}
if (navigator.appVersion.indexOf("Opera") != -1 || navigator.userAgent.indexOf("Opera") != -1) {
    quirksmode = "Opera";
}
var isOldIE = (quirksmode == "Opera" || quirksmode == "MSIE") ? 1 : 0;

if (quirksmode == "Opera") {
    if (is_minor < 9.21) {
        alert("Use of Opera older then 9.21 with this file manager is not recommended.");
    }
}


function handleSelectBoxMouseDown(e) {
    if (!checkselectenabled) {
        return;
    }


    var thisX = YAHOO.util.Event.getPageX(e);
    var thisY = YAHOO.util.Event.getPageY(e);
    if (quirksmode == "MSIE") {
        document.onselectstart = new Function("return false;");
    }
    var filewin = document.getElementById(checkarea); ;
    if (quirksmode == "Safari") {
        document.body.style.KhtmlUserSelect = "none";
    }
    if (quirksmode == "Mozilla") {
        filewin.style.MozUserSelect = "none";
    }
    if (quirksmode == "Opera") {
        document.onmousedown = function() {
            return false;
        };
    }

    selectWindowRegion = getRegion(filewin);

    selectMode = 1;
    selector = checkarea;
    if (scrollMode == 2) {
        selectStartScrollLeft = window.scrollX;
        selectStartScrollTop = window.scrollY;
        EU.addListener(window, "scroll", handleSelectBoxMove, this, true);
    } else {
        selectStartScrollLeft = filewin.scrollLeft;
        selectStartScrollTop = filewin.scrollTop;
        EU.addListener(filewin, "scroll", handleSelectBoxMove, this, true);
    }
    selectStartX = thisX;
    selectStartY = thisY;
    EU.addListener(document, "mouseup", handleSelectBoxUp, this, true);
    EU.addListener(document, "mousemove", handleSelectBoxMove, this, true);

    return false;
}

function handleSelectBoxUp(e) {
    if (!selectMode) {
        return;
    }

    selectMode = 0;

    handleSelections();
    EU.removeListener(document, "mouseup", handleSelectBoxUp);
    EU.removeListener(document, "mousemove", handleSelectBoxMove);

    // msie = filewin.unselectable = false;
    var filewin = document.getElementById(checkarea);
    if (quirksmode == "MSIE") {
        document.onselectstart = new Function("return true;");
    }
    if (quirksmode == "Safari") {
        document.body.style.KhtmlUserSelect = "";
    }
    if (quirksmode == "Mozilla") {
        filewin.style.MozUserSelect = "";
    }
    if (quirksmode == "Opera") {
        document.onmousedown = function() {
            return true;
        };
    }

    DOM.setStyle("select", "display", "none");
};


function handleSelectBoxMove(e) {

    if (!selectMode) {
        return false;
    }

    var selectel = document.getElementById("select");
    if (!selectel) {
        return;
    }

    var thisX = YAHOO.util.Event.getPageX(e);
    var thisY = YAHOO.util.Event.getPageY(e);

    if (selectMode == 1 && (Math.abs(thisY - selectStartY) > 2 || Math.abs(thisX - selectStartX) > 2)) {
        selectMode = 2;

        selectel.style.left = thisX + "px";
        selectel.style.top = thisY + "px";
        selectel.style.width = 0 + "px";
        selectel.style.height = 0 + "px";
        selectel.style.display = "block";

        rebuildLocCache();
        viewportHeight = YAHOO.util.Dom.getViewportHeight();

        for (var i in selectOvers) {
            delete selectOvers[i];
        }

    }

    if (selectMode != 2) {
        return;
    }

    YAHOO.util.Event.preventDefault(e);

    if (thisX == 0) {
        thisX = lastX;
    } else {
        lastX = thisX;
    }
    if (thisY == 0) {
        thisY = lastY;
    } else {
        lastY = thisY;
    }
    var windowLeft;
    var windowTop;
    var windowRight;
    var windowBottom;
    var windowWidth;
    var windowHeight;


    var ScrolledX;
    var ScrolledY;
    if (scrollMode == 2) {
        ScrolledX = 0;
        ScrolledY = 0;
        windowLeft = 0;
        windowTop = 0;
        windowRight = YAHOO.util.Dom.getDocumentWidth();
        windowBottom = YAHOO.util.Dom.getDocumentHeight();
        windowHeight = windowBottom;
        windowWidth = windowRight;
    } else {
        sWindow = document.getElementById(selector);
        ScrolledX = (sWindow.scrollLeft - selectStartScrollLeft); // X scrolled relative to the selectStartX
        ScrolledY = (sWindow.scrollTop - selectStartScrollTop); // Y scrolled relative to the selectStartY
        windowLeft = selectWindowRegion.left;
        windowTop = selectWindowRegion.top;
        windowRight = selectWindowRegion.right;
        windowBottom = selectWindowRegion.bottom;
        windowWidth = (windowRight - windowLeft);
        windowHeight = (windowBottom - windowTop);
    }

    /*
       We need to make two boxes
       The one the actual user sees, and the one that will be used to compare for
       file locations to see which files to select.  It is tricky because the window scrolls
       while this happens.  Also if the window is scrolled at all then all of our file locations are wrong
       and that has to be compensated for.
       */
    var FileBoxT, FileBoxB, FileBoxL, FileBoxR;

    /* The First Box is the FileBox
       It starts from where the mouse was first clicked, to where the mouse is now

       Its possible for the window to scroll while we are selecting, we want to increase the top of the
       to where it really started.  If we scrolled 400px, then all of our matches will be
       another 400px off.  But the trick is we want to include everything between where the mouse started +  the
       scroll amount.

       So if we scrolled 400px, we only need to increase the Top of the box.
       */
    if (thisY + ScrolledY > selectStartY) {

        /* scrolling down*/
        FileBoxT = selectStartY - ScrolledY;
        FileBoxB = thisY;
    } else {

        /* scrolling up*/
        FileBoxT = thisY;
        FileBoxB = selectStartY - ScrolledY;
    }
    if (thisX + ScrolledX > selectStartX) {

        /* scrolling right*/
        FileBoxL = selectStartX - ScrolledX;
        FileBoxR = thisX;
    } else {

        /* scrolling left*/
        FileBoxL = thisX;
        FileBoxR = selectStartX - ScrolledX;
    }

    /*
       Now it looks like what the user sees.
       */

    var SB = FileBoxB;
    var ST = FileBoxT;
    var SL = FileBoxL;
    var SR = FileBoxR;

    if (SB > windowBottom) {
        SB = windowBottom + 2;
        selectel.style.borderBottom = "";
    } else {
        selectel.style.borderBottom = "solid 2px #33c";
    }
    if (ST < windowTop) {
        ST = windowTop - 2;
        selectel.style.borderTop = "";
    } else {
        selectel.style.borderTop = "solid 2px #33c";
    }
    if (SL < windowLeft) {
        SL = windowLeft - 2;
        selectel.style.borderLeft = "";
    } else {
        selectel.style.borderLeft = "solid 2px #33c";
    }
    if (SR > windowRight) {
        SR = windowRight + 2;
        selectel.style.borderRight = "";
    } else {
        selectel.style.borderRight = "solid 2px #33c";
    }
    if (SB < ST) {
        SB = ST + 2;
    }
    if (SR < SL) {
        SR = SL + 2;
    }

    selectel.style.left = SL + "px";
    selectel.style.top = ST + "px";
    selectel.style.width = (SR - SL) + "px";
    selectel.style.height = (SB - ST) + "px";

    /*
       However we want to compensate for how much the window is currently scrolled.
       For example if the window has scrolled 300px, then all of our matching will
       be 300px off.   We would like to subtract the window scroll from each item, but we must instead
       at it to the file box.
       */
    FileBoxT += ScrolledY;
    FileBoxB += ScrolledY;
    FileBoxL += ScrolledX;
    FileBoxR += ScrolledX;

    /* Last we have to account for if the box is moved.  These a constant values supplied from the functions
       that track the window movement */

    //  FileBoxR += selectStartScrollLeft;
    //  FileBoxL += selectStartScrollLeft;
    //  FileBoxT += selectStartScrollTop;
    //  FileBoxB += selectStartScrollTop;


    var curRegion = new YAHOO.util.Region(FileBoxT, FileBoxR, FileBoxB, FileBoxL);

    /* document.getElementById('selecttest').style.left=FileBoxL+'px';
       document.getElementById('selecttest').style.top=FileBoxT+'px';
       document.getElementById('selecttest').style.width=(FileBoxR-FileBoxL)+'px';
       document.getElementById('selecttest').style.height=(FileBoxB-FileBoxT)+'px';*/
    var oldOvers = {};
    var outEvts = [];
    var enterEvts = [];
    var i;
    var len;

    // Check to see if the object we were selecting is no longer selected
    for (var i in selectOvers) {
        var loc = selectOvers[i];
        if (!loc) {
            continue;
        }

        if (!curRegion.intersect(loc)) {
            outEvts.push(i);
        }
        oldOvers[i] = true;
        delete selectOvers[i];
    }
    for (i in locCache) {
        var loc = locCache[i];
        if (!loc) {
            continue;
        }
        if (curRegion.intersect(loc)) {
            if (!oldOvers[i]) {
                enterEvts.push(i);
            }
            selectOvers[i] = loc;
        }
    }

    len = outEvts.length;
    for (i = 0; i < len; i++) {
        unselectFile(outEvts[i]);
    }

    len = enterEvts.length;
    for (i = 0; i < len; i++) {
        selectFile(enterEvts[i], 1);
    }

    var scrollAmt = 10;

    if (quirksmode == "Safari") {
        if (scrollMode == 2) {
            return false;
        }

        scrollAmt = 38;
        var thisDate = new Date();
        var thisTime = thisDate.getTime();
        if ((lastSelectTime + 100) < thisTime) {
            lastSelectTime = thisTime;
        } else {
            thisDate = null;
            thisTime = null;
            return false;
        }
        thisDate = null;
    }


    setmoveEvent();

    if (scrollMode == 2) {
        if ((thisY - window.scrollY) < 10) {
            scrollWindow(1, scrollAmt);
        }
        if (thisY > (viewportHeight - 10 + window.scrollY)) {
            scrollWindow(0, scrollAmt);
        }
    } else {
        var sWindow = document.getElementById(selector);
        if (windowTop > thisY) {
            scrollDiv(sWindow, 1, scrollAmt);
        } else if (viewportHeight - 10 < thisY) {
            scrollDiv(sWindow, 0, scrollAmt);
        }
    }

    //  if (windowLeft > thisX) { sWindow.scrollLeft > 10 ? sWindow.scrollLeft-=10 : sWindow.scrollLeft = 0; }
    //  if (windowRight < thisX) { (sWindow.scrollLeft < (sWindow.scrollWidth - 10)) ? sWindow.scrollLeft +=10 : sWindow.scrollLeft =  sWindow.offsetWidth;  }

    return false;
}


function scrollWindow(direction, amt) {

    // 0 = up, 1 = down
    if (amt == null) {
        amt = 12;
    }
    var didScroll = 0;
    var scrollAble = window.scrollMaxY - 10;
    if (direction == 1) {
        if (window.scrollY > amt) {
            window.scrollTo(0, window.scrollY - amt);
            didScroll = 1;
        } else if (window.scrollY == 0) {
            window.scrollTo(0, 0);
        } else {
            window.scrollY = 0;
        }
    } else if (direction == 0) {
        if (window.scrollY < (scrollAble + amt)) {
            window.scrollTo(0, window.scrollY + amt);
            didScroll = 1;
        } else if (scrollAble == window.scrollY) {
            didScroll = 0;
        } else {
            window.scrollTo(0, scrollAble);
            didScroll = 1;
        }
    }

    return didScroll;
}


function scrollDiv(divEl, direction, amt) {

    // 0 = up, 1 = down
    if (amt == null) {
        amt = 12;
    }
    var didScroll = 0;
    var scrollAble = (divEl.scrollHeight - divEl.offsetHeight);
    if (quirksmode == "MSIE") {
        scrollAble = divEl.scrollHeight;
    }
    if (direction == 1) {
        if (divEl.scrollTop > amt) {
            divEl.scrollTop -= amt;
            didScroll = 1;
        } else if (divEl.scrollTop == 0) {
            didScroll = 0;
        } else {
            divEl.scrollTop = 0;
        }
    } else if (direction == 0) {
        if (divEl.scrollTop < (scrollAble - amt)) {
            divEl.scrollTop += amt;
            didScroll = 1;
        } else if (scrollAble == divEl.scrollTop) {
            didScroll = 0;
        } else {
            divEl.scrollTop = scrollAble;
            didScroll = 1;
        }
    }

    return didScroll;
}


function getRegion(el) {
    return YAHOO.util.Region.getRegion(el);
}


function setmoveEvent(done) {
    done == 2 ? moveEvent = 0 : moveEvent = 1;
}

function rebuildLocCache() {
    locCache = {};
    var tagEl = document.getElementById(checkarea).getElementsByTagName("input");
    for (var i = 0; i < tagEl.length; i++) {
        if (!tagEl[i].id) {
            tagEl[i].id = "checkidgen" + checkidgen++;
        }
        if (tagEl[i].type != "checkbox") {
            continue;
        }

        locCache[tagEl[i].id] = getRegion(tagEl[i]);
    }
}

function unselectFile(ev) {

    //    YAHOO.util.Dom.get(ev).checked = false;
}

function selectFile(ev) {
    YAHOO.util.Dom.get(ev).checked = true;
}

function disableCheckSelect() {
    checkselectenabled = 0;
}

function enableCheckSelect() {
    checkselectenabled = 1;
}

function handleSelections() {}
