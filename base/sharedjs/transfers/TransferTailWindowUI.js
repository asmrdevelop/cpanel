(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;

    var PROGRESS_BAR_HEIGHT = 14;

    var TransferTailWindowUI = function(queue, windownum, sessionUIObj) {
        var ttwui = this;

        this._queue = queue;
        this._windownum = windownum;
        this._sessionUIObj = sessionUIObj;

        var headerContainerDiv = document.createElement("div");
        headerContainerDiv.id = "queue_" + queue + "_" + windownum + "_header_container";
        headerContainerDiv.className = this.windowHeaderContainerClassName;

        var headerDiv = document.createElement("div");
        headerDiv.id = "queue_" + queue + "_" + windownum + "_header";
        headerDiv.className = this.windowHeaderClassName;
        headerDiv.innerHTML = "queue_" + queue + "_" + windownum;

        var spinnerDiv = document.createElement("div");
        spinnerDiv.id = "queue_" + queue + "_" + windownum + "_spinner";
        spinnerDiv.className = this.windowSpinnerClassName;
        spinnerDiv.innerHTML = this._sessionUIObj.get_spinner_html();

        headerContainerDiv.appendChild(headerDiv);
        headerContainerDiv.appendChild(spinnerDiv);

        var bodyDiv = document.createElement("div");
        bodyDiv.id = "queue_" + queue + "_" + windownum;
        bodyDiv.className = this.windowClassName;


        var progressDiv = document.createElement("div");
        progressDiv.id = "queue_" + queue + "_" + windownum + "_progress";
        progressDiv.className = this.progressContainerClassName;

        var containerDiv = document.createElement("div");
        containerDiv.id = "queue_" + queue + "_" + windownum + "_container";
        containerDiv.className = this.windowContainerClassName;

        containerDiv.appendChild(headerContainerDiv);
        containerDiv.appendChild(bodyDiv);
        containerDiv.appendChild(progressDiv);

        this.containerElement = containerDiv;
        this.bodyElement = bodyDiv;
        this._headerElement = headerDiv;
        this._progressElement = progressDiv;
        this.spinner = spinnerDiv;

        if (!YAHOO.env.ua.ie || YAHOO.env.ua.ie >= 9) {
            this._progressBar = new YAHOO.widget.ProgressBar({
                width: parseInt(bodyDiv.offsetWidth),
                anim: ttwui._sessionUIObj.get_should_animate(),
                height: PROGRESS_BAR_HEIGHT
            }).render(progressDiv);

            YAHOO.util.Event.on(window, "resize", this.render, this, true);
        }
    };

    YAHOO.lang.augmentObject(TransferTailWindowUI.prototype, {
        progressContainerClassName: "window_progress",
        windowHeaderClassName: "window_header",
        windowHeaderContainerClassName: "window_header_container",
        windowContainerClassName: "window_container",
        windowSpinnerClassName: "window_spinner",
        windowClassName: "window",

        setProgressBarPercentage: function(percentage) {
            if (this._progressBar) {
                /* hack to not animate to zero */
                var original_anim;
                if (percentage === 0) {
                    original_anim = this._progressBar.get("anim");
                    this._progressBar.set("anim", null);
                }

                this._progressBar.set("value", percentage);

                if (original_anim) {
                    this._progressBar.set("anim", original_anim);
                }
            }
        },

        set_item: function(item) {
            this.bodyElement.innerHTML = "";
            this._headerElement.innerHTML = item.html_encode();
            this.spinner.style.display = this._sessionUIObj.get_should_animate() ? "" : "none";
        },

        render: function() {
            if (this._progressBar) {
                this._progressBar.set("width", parseInt(this.bodyElement.offsetWidth));
            }
        }
    });

    window.TransferTailWindowUI = TransferTailWindowUI;

}(window));
