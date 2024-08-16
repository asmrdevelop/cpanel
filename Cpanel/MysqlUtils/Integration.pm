package Cpanel::MysqlUtils::Integration;

# cpanel - Cpanel/MysqlUtils/Integration.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;
use Cpanel::SafeRun::Object     ();
use Cpanel::ForkAsync           ();
use Cpanel::Locale              ();
use Cpanel::Logger              ();
use Cpanel::Encoder::Tiny       ();
use Cpanel::IOCallbackWriteLine ();

my $locale;

our $SCRIPT_PATH    = '/usr/local/cpanel/bin';
our %UPDATE_SCRIPTS = (
    'phpMyAdmin' => 'update_phpmyadmin_config',
    'Roundcube'  => 'update-roundcube-db',
    'DBcache'    => 'update_db_cache',
);

sub update_apps_that_use_mysql {
    my ($args) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    local $SIG{'PIPE'} = 'IGNORE';
    local $SIG{'HUP'}  = 'IGNORE';

    foreach my $update_script_name ( sort keys %UPDATE_SCRIPTS ) {
        my $update_script = $UPDATE_SCRIPTS{$update_script_name};

        print $locale->maketext( "Updating “[_1]” configuration …", $update_script_name ) . " ";

        try {
            Cpanel::Logger::redirect_stderr_to_error_log();

            if ( !-x "$SCRIPT_PATH/$update_script" ) {

                # not shown
                die "$SCRIPT_PATH/$update_script is not executable";
            }

            my $run = Cpanel::SafeRun::Object->new(
                'program' => "$SCRIPT_PATH/$update_script",
                'stdout'  => Cpanel::IOCallbackWriteLine->new(
                    sub {
                        my ($line) = @_;
                        if ( $args && $args->{html} ) {
                            print Cpanel::Encoder::Tiny::safe_html_encode_str($line);
                        }
                        else {
                            print $line;
                        }
                    }
                )
            );

            print STDERR $run->stderr() if $run->stderr();

            if ( $run->CHILD_ERROR() ) {
                print $locale->maketext("Failed …") . "\n" . $run->autopsy();
            }
            else {
                print $locale->maketext("Success …");
            }
        }
        catch {
            print $locale->maketext("Failed …") . ' ' . $locale->maketext( "Could not execute “[_1]”.", "$SCRIPT_PATH/$update_script" );
        };

        print $locale->maketext("Done") . "\n";
    }

    return 1;
}

sub update_apps_that_use_mysql_in_background {

    # Closing STDOUT, since subprocess output will break JSON formatting for apitool.
    close STDOUT if fileno(STDOUT);
    my $ignore_stdout = open STDOUT, '>', '/dev/null';

    my $pid = Cpanel::ForkAsync::do_in_child( \&update_apps_that_use_mysql );

    return ( $pid, 'ok' );
}

1;
