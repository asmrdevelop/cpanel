(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;

    var TransferQueueWindowUI = function(queue, sessionUIObj) {
        var self = this;
        this._sessionUIObj = sessionUIObj;
        this._queue = queue;

        /* Create the Window for the queue group */
        var queueContainerDiv = document.createElement("div");
        queueContainerDiv.id = "queue_" + queue + "_container";
        queueContainerDiv.className = "queue_container col-md-6";
        sessionUIObj.get_queue_el().appendChild(queueContainerDiv);

        var queuePanelDiv = document.createElement("div");
        queuePanelDiv.className = "panel panel-default";
        queueContainerDiv.appendChild(queuePanelDiv);

        var queueDiv = document.createElement("div");
        queueDiv.id = "queue_" + queue;
        queueDiv.className = "window_group panel-heading";
        queuePanelDiv.appendChild(queueDiv);

        var queueOutputDiv = document.createElement("div");
        queueOutputDiv.id = "queue_" + queue + "_output";
        queueOutputDiv.className = "queue_output panel-body";
        queuePanelDiv.appendChild(queueOutputDiv);

        var divHeader = document.createElement("div");
        divHeader.id = "queue_" + queue + "_header";
        divHeader.className = "queue_header";

        var divTitle = document.createElement("div");
        divTitle.innerHTML = queue;
        divTitle.id = "queue_" + queue + "_title";
        divTitle.className = "queue_title";
        divHeader.appendChild(divTitle);

        var new_percentage_divTxt = document.createElement("div");
        new_percentage_divTxt.id = "queue_" + queue + "_progress_text";
        new_percentage_divTxt.className = "queue_percentage";
        new_percentage_divTxt.innerHTML = LOCALE.maketext("[_1]%", 0);
        divHeader.appendChild(new_percentage_divTxt);

        /* End the Window for the queue processor */

        /* now the progress bar for the overall group progress */
        var progressContainerDiv = document.createElement("div");
        progressContainerDiv.id = "queue_" + queue + "_progress_container";
        progressContainerDiv.className = "queue_progress_container";

        var progressBarDiv = document.createElement("div");
        progressBarDiv.id = "queue_" + queue + "_progress";
        progressBarDiv.className = "queue_progress";

        progressContainerDiv.appendChild(progressBarDiv);

        queueDiv.appendChild(divHeader);
        queueDiv.appendChild(progressContainerDiv);

        this._progressBar = new YAHOO.widget.ProgressBar({
            width: parseInt(progressContainerDiv.offsetWidth),
            height: 14,
            anim: this._sessionUIObj.get_should_animate()
        }).render(progressBarDiv);
        /* end the progress bar */

        this.render = function() {
            self._progressBar.set("width", parseInt(progressContainerDiv.offsetWidth));
        };
        this._progressTextEl = new_percentage_divTxt;
        this.outputEl = queueOutputDiv;
        this.windowGroupEl = queueDiv;
        this.windowCount = 0;

        YAHOO.util.Event.addListener(window, "resize", this.render);
    };

    YAHOO.lang.augmentObject(TransferQueueWindowUI.prototype, {
        addWindow: function(windowEl) {
            this.windowCount++;
            this.windowGroupEl.appendChild(windowEl);
        },

        setProgressBarPercentage: function(percentage) {
            this._progressBar.set("value",percentage);
            this._progressTextEl.innerHTML = percentage + "%";
        },

        queue: function() {
            return this._queue;
        }
    });

    window.TransferQueueWindowUI = TransferQueueWindowUI;

}(window));
