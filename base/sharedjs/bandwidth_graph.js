/* eslint-disable camelcase */
// external requirements:
//  d3
//
// cPanel requirements:
//  chart_utilities.js

// ----------------------------------------------------------------------
// NOTE: ABANDON ALL HOPE, YE WHO ENTER HERE WITHOUT KNOWING D3.js!
//
// Actually, it’s not that bad :), but seriously, before maintaining this
// code, please familiarize yourself with D3.js.
// ----------------------------------------------------------------------

( function(window) {
    "use strict";

    var d3 = window.d3;
    var Chart_Utilities = window.Chart_Utilities;

    var GRAPH_WIDTH = 620;
    var GRAPH_HEIGHT = 200;

    // order determines graph order
    function sort_nums(a, b) {
        return a - b;
    }

    var resolution_interval = {
        "5min": 300000,
        hourly: 3600000,
        daily: 86400000
    };

    function draw_protocols_time_graph_key(opts) {
        var protocols_order = opts.protocols_order;
        var container_path = opts.container_path;

        var D3_COLOR = d3.scale.category10()
            .domain(protocols_order)
          ;


        var key_sel = d3
            .select(container_path)
            .append("div")
            .classed("graph-key", true)
        ;

        // This is a simple example of a D3 “data join”.
        // For more information, see: http://bost.ocks.org/mike/join/
        //
        var key_item = key_sel
            .selectAll(".key-item")
            .data(protocols_order)
            .enter()
            .append("span")
            .classed("key-item", true)
        ;

        // For each key item, create a color sample.
        key_item
            .append("span")
            .classed("color-sample", true)
            .style("background-color", function(d) {
                return D3_COLOR(d);
            })
        ;

        // For each key item, add the text.
        key_item
            .append("span")
            .classed("field-name", true)
            .html( function(d) {
                return "&nbsp;" + d.toUpperCase();
            } )
        ;
    }

    // Returns whether it actually drew a chart, or just put in the
    // text that says there’s no data.
    //
    // options (in a hash):
    //
    //  container_path      a selector that points to where to draw the graph
    //
    //  api_protocol_data   data from UAPI’s Bandwidth::query
    //                      For example:
    //                          {
    //                              imap: {
    //                                  <unixtime>: 12345,
    //                                  ...
    //                              },
    //                              ...
    //                          }
    //
    //  min_date            a Date object, earliest date on the X axis
    //
    //  resolution          text, how long of a time each data result
    //                      represents: "5min", "hourly", "daily"
    //
    //  time_format         d3 axis tickFormat argument
    //
    //  time_ticks          OPTIONAL, d3 axis tickValues argument
    //
    function draw_protocols_time_graph(opts) {
        var rear_opts = Object.create(opts);

        rear_opts.data = opts.api_protocol_data;
        rear_opts.protocols_order = opts.protocols_order;

        return _draw_time_graph(rear_opts);
    }

    function _draw_time_graph(opts) {
        var container_path = opts.container_path;
        var data_in = opts.data;
        var graph_protocols = opts.protocols_order;

        var D3_COLOR = d3.scale.category10()
            .domain(graph_protocols)
          ;


        // TODO: Maybe better to let the caller handle putting in the text?
        if ( !Object.keys(data_in).length ) {
            d3.select(container_path)
                .text(LOCALE.maketext("There is no data for this period."));
            return false;
        }

        var MIN_TIME = opts.min_date;
        var RESOLUTION = resolution_interval[opts.resolution];

        var time_format = opts.time_format;
        var time_ticks = opts.time_ticks; // optional

        var MAX_TIME = opts.max_date ? new Date(opts.max_date) : new Date();

        // Inspired by the example at: http://bl.ocks.org/mbostock/3885211

        var margin = { top: 20, right: 20, bottom: 30, left: 120 },
            width = GRAPH_WIDTH - margin.left - margin.right,
            height = GRAPH_HEIGHT - margin.top - margin.bottom;

        var svg = d3
            .select(container_path)
            .append("svg")
            .attr("width", GRAPH_WIDTH)
            .attr("height", GRAPH_HEIGHT)
            .append("g")
            .attr("transform", "translate(" + margin.left + "," + margin.top + ")")
        ;

        var x_scale = d3.time.scale().range( [0, width] )
            .domain( [ MIN_TIME, MAX_TIME ] )
        ;
        var x_axis = d3.svg.axis()
            .scale(x_scale)
            .orient("bottom")
            .tickFormat(time_format)
        ;

        if (time_ticks) {
            x_axis.tickValues(time_ticks);
        }

        svg.append("g")
            .attr("class", "x axis")
            .attr("transform", "translate(0," + height + ")")
            .call(x_axis);

        var protocol_data = {};

        // If we could rely on D3 for the y-axis tick marks, we wouldn’t
        // need this; however, since we’re converting 1,024 bytes to 1 KB,
        // 1,048,576 btyes to 1 MB, and so on up, we can’t depend on D3 to
        // give us nice, even-looking tick marks; if we did, we’d end up with
        // stuff like 488.28 KB instead of “500,000 bytes”.
        //
        // We need to sum the totals for each sample so that we know the max
        // value on the y domain to pass into our custom scaler method.
        var total_data_per_time = {};

        var protocol_max_unixtime = {};
        var min_unixtime = Math.floor( Date.now() / 1000 );

        graph_protocols.forEach( function(ptcl) {
            protocol_data[ptcl] = [];

            if (data_in[ptcl]) {
                var unixtimes = Object.keys(data_in[ptcl]).sort(sort_nums);
                protocol_max_unixtime[ptcl] = unixtimes[ unixtimes.length - 1 ];

                if (unixtimes[0] < min_unixtime) {
                    min_unixtime = unixtimes[0];
                }
            }
        } );

        var bytes_per_minute;
        var bytes_divisor = RESOLUTION / 60 / 1000;

        // For a stacked graph it’s important that each time point
        // have an entry for each dataset. So, go through and, if there’s
        // data missing for some point, set it to 0.

        var cur_time = new Date(min_unixtime * 1000);

        // In this loop we munge the data from what cPanel UAPI gives us
        // into a format that D3.js can use.
        //
        while (cur_time < MAX_TIME) {
            var cur_date = new Date(cur_time);
            cur_time.setMilliseconds( RESOLUTION + cur_time.getMilliseconds() );

            // Ignore anything from before the graph’s time period.
            if (cur_date < MIN_TIME) {
                continue;
            }

            var unixtime = cur_date.getTime() / 1000;

            if ( !(unixtime in total_data_per_time) ) {
                total_data_per_time[unixtime] = 0;
            }

            // Iterate through the protocols in the passed-in order, not the
            // data’s, since the data hash could put them into any order.
            // This will make the graph “stack” be in the intended order.
            for (var p = 0; p < graph_protocols.length; p++) {
                var ptcl = graph_protocols[p];

                // Ignore any protocol for which there is no data.
                if ( !protocol_max_unixtime[ptcl] ) {
                    continue;
                }

                var p_data = data_in[ptcl];

                // Convert the a sum for the RESOLUTION period into
                // a rate.
                //
                bytes_per_minute = p_data[unixtime];
                if (bytes_per_minute) {
                    bytes_per_minute /= bytes_divisor;

                    // Increment the total data count for this
                    // sample time.
                    total_data_per_time[unixtime] += bytes_per_minute;
                }

                // NB: If there’s any data at all for this protocol,
                // then D3 needs a data figure for every time point.
                //
                protocol_data[ptcl].push( {
                    date: cur_date,
                    y: bytes_per_minute || 0
                } );
            }
        }

        // Finally, we package the protocol_data values into hashes,
        // which lets us coordinate a dataset with the right protocol below.
        // Might as well strip out any empty datasets while we’re in here.
        var graph_data = graph_protocols.slice().reverse().map( function(ptcl) {
            if ( protocol_data[ptcl].length ) {
                return {
                    protocol: ptcl,
                    values: protocol_data[ptcl]
                };
            }

            return false;
        } ).filter(Boolean);    // i.e., strip out anything that’s not truth-y

        var stack = d3.layout.stack()
            .values(function(d) {
                return d.values;
            });

        // This will add y0 entries to the protocol_data arrays.
        var stacked_data = stack(graph_data);

        var tick_values = Chart_Utilities.get_tick_values_for_format_bytes(
            d3.max( d3.values(total_data_per_time) )
        );

        // Now that we have the max Y value, we can build the axis and scale.

        var y_scale = d3.scale.linear()
            .range( [height, 0] )
            .domain(
                [ 0, tick_values[ tick_values.length - 1 ] ]
            )
        ;

        var y_axis = d3.svg.axis()
            .scale(y_scale)
            .orient("left")
            .tickFormat( function(b) {
                return b ? LOCALE.maketext("[format_bytes,_1]/min.", b) : "";
            } )
            .tickValues(tick_values)
        ;

        svg.append("g")
            .attr("class", "y axis")
            .call(y_axis)
        ;

        var area = d3.svg.area()
            .x( function(d) {
                return x_scale(d.date);
            } )
            .y0( function(d) {
                return y_scale(d.y0);
            } )
            .y1( function(d) {
                return y_scale(d.y0 + d.y);
            } )
            .interpolate("step-after");

        // ----------------------------------------------------------------------

        var protocol_svg = svg.selectAll(".protocol")
            .data(stacked_data)
            .enter().append("g")
            .attr("class", "protocol")
        ;

        protocol_svg.append("path")
            .attr("class", "area")
            .attr("d", function(d) {
                return area(d.values);
            })
            .style("fill", function(d) {
                return D3_COLOR(d.protocol);
            })
        ;

        return true;
    }

    window.Bandwidth_Graph = {
        draw_protocols_time_graph: draw_protocols_time_graph,
        draw_protocols_time_graph_key: draw_protocols_time_graph_key
    };
}(window) );
