if ( "PieRenderer" in $.jqplot ) {
    var _old_init = $.jqplot.PieRenderer.prototype.init;
    $.jqplot.PieRenderer.prototype.init = function() {

        // prop: startingAngle
        // angular displacement from right horizontal for first slice
        this.startingAngle = 0;
        return _old_init.apply( this, arguments );

        // prop: sliceBorderWidth
        // width of a border to draw around each pie slice
        this.sliceBorderWidth = 0;
    };

    var _old_drawSlice = $.jqplot.PieRenderer.prototype.drawSlice;
    $.jqplot.PieRenderer.prototype.drawSlice = function(ctx, ang1, ang2, color, isShadow) {

        // NB: IE sometimes draws a full circle if ang1==ang2. Gr.
        if ( ang1 == ang2 ) {
            return;
        }

        ang1 += this.startingAngle;
        ang2 += this.startingAngle;
        var return_value = _old_drawSlice.call( this, ctx, ang1, ang2, color, isShadow );

        if ( this.fill && this.sliceBorderWidth && !isShadow ) {
            ctx.save();
            ctx.strokeStyle = "#ffffff";
            ctx.lineWidth = this.sliceBorderWidth;
            ctx.stroke();
            ctx.restore();
        }

        return return_value;
    };

    if ( !( "CPANEL" in window ) ) {
        CPANEL = {};
    }
    CPANEL._pie_chart_options = function() {};
    CPANEL._pie_chart_options.prototype = {
        title: { show: false },
        seriesDefaults: {
            renderer: $.jqplot.PieRenderer,
            rendererOptions: {
                padding: 5,
                shadowOffset: 1,
                startingAngle: -1 * Math.PI / 2,
                sliceBorderWidth: 1.5
            }
        },
        gridPadding: {
            top: 5,
            right: 5,
            bottom: 5,
            left: 5
        },
        grid: {
            shadowDepth: 0,
            borderWidth: 0,
            borderColor: "transparent",
            background: "transparent"
        }
    };
}  // end pie fixes

// partially fix the fact that VML can't handle a "transparent" background
var _old_grid_draw = $.jqplot.CanvasGridRenderer.prototype.draw;
$.jqplot.CanvasGridRenderer.prototype.draw = function() {
    var grid_is_blank =
        this.background == "transparent"
        && !this.drawGridLines
        && ( this.borderColor == "transparent" || this.borderWidth == 0 )
    ;

    if ( grid_is_blank ) {
        return;
    } else {
        return _old_grid_draw.apply( this, arguments );
    }
};
