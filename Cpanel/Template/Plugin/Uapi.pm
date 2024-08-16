package Cpanel::Template::Plugin::Uapi;

# cpanel - Cpanel/Template/Plugin/Uapi.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';

use Cpanel::API ();

sub new {
    my ($class) = @_;
    my $plugin = { 'exec' => \&_uapi_exec };

    return bless $plugin, $class;
}

sub _uapi_exec {
    my ( $module, $func, $params_hr ) = @_;

    my $results = Cpanel::API::execute( $module, $func, $params_hr );

    if ( $params_hr->{'api.normalize'} ) {
        my $meta = $results->{'metadata'};
        if ( $meta && $meta->{'paginate'} ) {
            $meta->{'paginate'}->{'total_records'} = $meta->{'paginate'}->{'total_results'};
            delete $meta->{'paginate'}->{'total_results'};
            $meta->{'paginate'}->{'current_record'} = $meta->{'paginate'}->{'start_result'};
            delete $meta->{'paginate'}->{'start_result'};
            $results->{'meta'} = $meta;
            delete $results->{'metadata'};
        }
        delete $results->{'_done_sorts'};
        delete $results->{'_done_pagination'};
    }

    return $results;
}

1;
