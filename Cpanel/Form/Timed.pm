package Cpanel::Form::Timed;

# cpanel - Cpanel/Form/Timed.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
##no critic(RequireUseWarnings)

use Cpanel::Form    ();
use Cpanel::JSONAPI ();

our $VERSION = 0.1;

sub timed_parseform {
    my $timeout      = shift || 360;
    my $timeout_func = shift || sub { die(@_); };
    my $fh           = shift || undef;
    my $file_uploads = shift || 0;
    my $orig_alarm;
    my $form_ref;

    my $start_time = time();
    {
        local $Cpanel::Form::file_uploads_allowed = $file_uploads;
        local $SIG{'ALRM'} = sub { $timeout_func->("Your request could not be processed during the allowed timeframe."); };
        $orig_alarm = alarm($timeout);

        if ( Cpanel::JSONAPI::is_json_request() ) {
            $form_ref = Cpanel::JSONAPI::parsejson($fh);
        }
        else {
            $form_ref = Cpanel::Form::parseform($fh);
        }

        my $new_alarm = $orig_alarm - ( time() - $start_time );
        if ( $orig_alarm > 0 ) {
            alarm( $new_alarm > 0 ? $new_alarm : 1 );
        }
        else {
            alarm(0);
        }
    }
    return $form_ref;
}

1;
