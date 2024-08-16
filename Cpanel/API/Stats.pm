
# cpanel - Cpanel/API/Stats.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::Stats;

use strict;
use warnings;

use Cpanel::Stats ();

=head1 MODULE

C<Cpanel::API::Stats>

=head1 DESCRIPTION

C<Cpanel::API::Stats> provides UAPI methods for retrieving information concerning the statistics products
enabled in cPanel such as webalizer and awstats.

=head1 FUNCTIONS

=head2 list_sites($args, $result)

Get information about location and status of supported stats engines and
traffic types.

=head3 ARGUMENTS

=over 1

=item $args - an instance of L<Cpanel::Args>

=over 1

Supported arguments in $args:

=over

=item engine - string - required - the stats engine, such as webalizer.

=item traffic - string - the traffic type such as ftp, defaults to http.

=back

=back

=item $result - an instance of L<Cpanel::Result>

=over 1

The $result->data() method will return the API response.
The API response will contain a list of hashrefs for each domain stats are available for.
Each hashref contains:

=over

=item ssl - boolean 0 or 1 - whether this is for an SSL host.

=item path - string - URI encoded path to the stats page.

=item domain - the domain the stats are for.

=item all_domains - boolean - 1 when the statistics link is for all the users domains.

=back

=back

=back

=head3 RETURNS

Returns 1

=head3 THROWS

=over

Any error messages will be stored in the L<Cpanel::Result> $result->errors() list.

=over

=item When the web server role is not set for the server.

=item When the cPanel account does not have the 'stats' feature.

=item When the engine parameter is invalid.

=item When the traffic parameter is invalid.

=back

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty Stats list_sites engine=webalizer

The returned data will contain a structure similar to the JSON below:

    "data" : {
            "domain" : "domain.tld",
            "ssl" : 1,
            "all_domains" : 0,
            "path" : "/tmp/cpuser/webalizer/index.html"
         }

=head4 Template Toolkit

    [%  SET result = execute("Stats", "list_sites", {'engine' => 'webalizer'}); %]
    [%  IF result.status %]
        <ul>
        [% FOREACH data IN result.data %]
            <li><a href="[% CPANEL.ENV.cp_security_token _ data.path %]">[% data.domain %]</a></li>
        [% END %]
        </ul>
    [% END %]

=cut

sub list_sites {
    my ( $args, $result ) = @_;

    my $traffic = $args->get('traffic') // 'http';
    $result->data(
        [
            Cpanel::Stats::list_sites_stats(
                $args->get_length_required('engine'),
                $traffic
            )
        ]
    );

    return 1;
}

=head2 get_site_errors()

Retrieve lines from various error logs in reverse chronological order for a specific domain.

=head3 ARGUMENTS

=over 1

=item domain - string - required

The domain name of the site.

=item maxlines - integer -

The maximum number of lines to retrieve. Can be within the range of 1-5000. Defaults to 300.

=item log - string -

The log to query. Default is C<error>.

Supported options:

=over 1

=item error - The web server error log. With the error log, the method only returns lines that include the users home directory.

=item suexec - The suexec log if present. With the suexec log, the method only returns lines that include the users home directory or the cPanel user name.

=back

=back

=head3 RETURNS

A list of hashrefs for each log line, or empty list if no lines are returned. Each hashref contains:

=over

=item date - UNIX epoch timestamp.

B<Note> The date can be undefined/null in the case where the system cannot parse the date from the log line.

=item entry - string - the full log line

=back

=head3 THROWS

=over

=item When the web server role is not set for the server.

=item When the C<errorlog> feature is not enabled for the account.

=item When the domain is not valid.

=item When C<maxlines> is not between 1-5000 inclusive.

=item When the log parameter is not valid.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=metwx Stats get_site_errors domain=cpanel.net --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    "data" : {
            [
              {
                "entry" : "[Fri Feb 13 19:58:23.420593 2009] [core:error] [pid 29227:tid 47876185720576] (13)Permission denied: [client 10.0.0.2:62908] AH00132: file permissions deny server access: /home/user/public_html/index.html",
                "date" : 1234576703
              },
              {
                "entry" : "[Fri Feb 13 19:58:24.420593 2009] [core:error] [pid 29228:tid 47876185720577] (13)Permission denied: [client 10.0.0.2:62908] AH00132: file permissions deny server access: /home/user/public_html/index.html",
                "date" : 1234576704
              }
            ]
         }

=head4 Template Toolkit

    [%  SET result = execute("Stats", "get_site_errors", {'domain' => 'cpanel.net'}); %]
    [%  IF result.status %]
        <pre>
            [% FOREACH line IN result.data %]
                [% line.entry %]
            [% END %]
        </pre>
    [% END %]

=cut

sub get_site_errors {
    my ( $args, $result ) = @_;

    my $domain   = $args->get_length_required('domain');
    my $log      = $args->get('log')      // 'error';
    my $maxlines = $args->get('maxlines') // 300;
    $result->data( Cpanel::Stats::list_site_errors( $domain, $log, $maxlines ) );
    return 1;
}

=head2 list_stats_by_domain()

=head3 ARGUMENTS

=over

=item engine

The statistics reporting engine. Currently we only support C<analog>.

=item domain

The user's domain you want monthly reports from.

=item ssl - Boolean

When 1 returns ssl access reports. When 0 returns non-ssl access reports. Defaults to 1.

=back

=head3 RETURNS

Array ref where each element of the array is a hash ref with the following structure:

=over

=item date - Unix timestamp

The month and year encoded as a timestamp. Note: Other fields in the date are fixed so
for Aug 2019, the date is set as 2019-08-01 00:00:00.

=item url - string

A session-relative URL used to access the month's statistics reports.

=back

=head3 THROWS

=over

=item When the user does not have permission to use this feature.

=item When the engine parameter is not provided.

=item When the engine requested is not valid for this API.

=item When the domain parameter is not provided.

=item When the domain requested is not owned by the current cPanel user.

=item When the ssl parameter is not a valid Boolean.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    uapi --user=cpuser --output=jsonpretty Stats list_stats_by_domain engine=analog domain=cptest.tld ssl=1

The returned data will contain a structure similar to the JSON below:

    "data" : [
     {
        "date" : 1564617600,
        "url" : "tmp/cptest/analog/8.html"
     },
     {
        "date" : 1556668800,
        "url" : "tmp/cptest/analog/5.html"
     },
     {
        "url" : "tmp/cptest/analog/4.html",
        "date" : 1554076800
     }
   ],

=head4 Template Toolkit

    [%
    SET result = execute('Stats', 'list_stats_by_domain', {
        domain => 'cptest.tld',
        ssl    => 1,
    });
    IF result.status;
       FOR item IN result.data %]
       <a href="[% CPANEL.ENV.cp_security_token %]/[% item.url %]">
        [% locale.datetime(item.date) %]
       </a>
       [% END;
    END %]

=cut

sub list_stats_by_domain {
    my ( $args, $result ) = @_;

    $result->data(
        Cpanel::Stats::list_stats_by_domain_group_by_month(
            $args->get_length_required('engine'),
            $args->get_length_required('domain'),
            $args->get('ssl') // 1,
        )
    );
    return 1;
}

=head2 get_bandwidth()

Retrieves a list of bandwidth records sorted by the date, the protocol and the domain.

Sorting rules are a little complex:

=over

=item - records are sorted by date with newest bandwidth records first.

=item - protocols are sorting in the following order

=over

=item 1) http

=item 2) ftp

=item 3) imap

=item 4) pop3

=item 5) smtp

=back

=item - for http traffic, the primary domain is listed first and the other domains are listed in alphabetical order.

=back

=head3 RETURNS

An arrayref of hashrefs with the following structure:

=over

=item month_start - unix timestamp

Only the month and year are significant. Ignore all other parts of the date.

=item domain

Domain the traffic belongs to. Only applicable to http traffic.

=item protocol - string

=over

=item - http

=item - ftp

=item - imap

=item - pop3

=item - smtp

=back

=item bytes - number

Bytes of bandwidth consumed for the domain/protocol for the month indicated in month_start.

=back

=head3 THROWS

=over

=item When the user does not have the bandwidth feature enabled.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    uapi --user=cpuser --output=jsonpretty Stats get_bandwidth

The returned data will contain a structure similar to the JSON below:

    "data" : [
         {
            "domain" : "cpuser.com",
            "bytes" : 22000,
            "protocol" : "http",
            "month_start" : 1564635600
         },
         {
            "protocol" : "http",
            "month_start" : 225444,
            "domain" : "addon.com",
            "bytes" : 1551546238
         },
         {
            "bytes" : 345543,
            "domain" : "wordpress.cpuser.com",
            "protocol" : "http",
            "month_start" : 1564635600
         },
         {
            "month_start" : 1564635600,
            "protocol" : "ftp",
            "bytes" : 675,
            "domain" : "tommy.tld"
         },
         {
            "bytes" : 44500,
            "domain" : "tommy.tld",
            "protocol" : "imap",
            "month_start" : 1564635600
         },
         {
            "month_start" : 1564635600,
            "protocol" : "pop3",
            "bytes" : 0,
            "domain" : "tommy.tld"
         },
         {
            "protocol" : "smtp",
            "month_start" : 1564635600,
            "bytes" : 443309,
            "domain" : "tommy.tld"
         }
    ]

=head4 Template Toolkit

The following example will generated a monthly bandwidth report similar
to that reported in cPanel Bandwidth application.

    [%
    SET result = execute('Stats', 'get_bandwidth', {});
    IF result.status;
        SET total = 0;
        SET last_date = result.data.0.month_start;
        SET period_printed = 0;

        FOREACH record IN result.data;
            SET current_date = record.month_start;
            IF current_date != last_date;
                # Print the total for the month
                'Total = ' _ total;
                SET total = 0;
                SET last_date = current_date;
                SET period_printed = 0;
            ELSE;
                IF !period_printed;
                    USE month = date(time => record.month_start, format => '%B %Y');
                    # Print the Month Year section title
                    month;
                    period_printed = 1;
                END;
                total = total + record.bytes;
                IF record.protocol == 'http';
                   # Print the domain report
                   record.protocol _ '-' _ record.domain _ ' = ' _ record.bytes;
                ELSE;
                   # Print the non-domain report
                   record.protocol _ ' = ' _ record.bytes;
                END;
            END;
        END;
    END %]

=cut

sub get_bandwidth {
    my ( $args, $result ) = @_;

    require Cpanel::APITimezone;
    my $timezone = Cpanel::APITimezone::get_uapi_timezone($args);

    $result->data(
        Cpanel::Stats::get_bandwidth( timezone => $timezone ),
    );

    return 1;
}

my $stats_non_mutating = {
    needs_role    => 'WebServer',
    needs_feature => { match => 'any', features => [ 'webalizer', 'analog' ] },
    allow_demo    => 1,
};

my $errors_non_mutating = {
    needs_role    => 'WebServer',
    needs_feature => 'errlog',
    allow_demo    => 1,
};

our %API = (
    get_site_errors      => $errors_non_mutating,
    get_bandwidth        => { 'needs_feature' => 'bandwidth', 'allow_demo' => 1 },
    list_sites           => $stats_non_mutating,
    list_stats_by_domain => $stats_non_mutating,
);

1;
