package Cpanel::Rsync;

# cpanel - Cpanel/Rsync.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Binaries                  ();
use Cpanel::Parser::Rsync             ();
use Cpanel::SafeRun::Object           ();
use Cpanel::ExitValues::rsync         ();
use Cpanel::Exception                 ();
use Cpanel::CPAN::IO::Callback::Write ();
use Cpanel::AccessIds::SetUids        ();
use Cpanel::OS                        ();

=pod

=encoding utf-8

=head1 NAME

Cpanel::Rsync - An interface to calling rsync

=head1 SYNOPSIS

    use Cpanel::Rsync ();

    Cpanel::Rsync->run(
        'setuid' => [ 'bob' ],
        'args'   => [
            '--force',
            '/source/dir/' => '/target/dir/',
        ]
    );

=cut

our $MAX_RSYNC_READ_WAIT_TIMEOUT = ( 60 * 180 );            # 180 minutes
our $TIMEOUT                     = ( 60 * 60 * 24 * 3 );    # 3 Days

sub run ( $, %OPTS ) {

    my $args   = $OPTS{'args'} or die Cpanel::Exception::create( 'MissingParameter', [ name => 'args' ] );
    my $setuid = $OPTS{'setuid'};

    my $rsync_bin = Cpanel::Binaries::path('rsync');
    -x $rsync_bin or die Cpanel::Exception->create_raw("The system is missing the “rsync” binary.");

    my $rsync_parser = Cpanel::Parser::Rsync->new();

    my $saferun = Cpanel::SafeRun::Object->new(
        'program'      => $rsync_bin,
        'read_timeout' => $MAX_RSYNC_READ_WAIT_TIMEOUT,
        'timeout'      => $TIMEOUT,
        'args'         => [
            Cpanel::OS::rsync_old_args()->@*,
            '--progress',
            '--human-readable',
            '--archive',
            '--verbose',
            @{$args},
        ],
        'stdout' => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                $rsync_parser->process_data(@_);
            }
        ),
        ( $setuid ? ( 'before_exec' => sub { Cpanel::AccessIds::SetUids::setuids( @{$setuid} ) } ) : () ),
        'stderr' => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                $rsync_parser->process_error_data(@_);
            }
        )
    );

    if ( $saferun->CHILD_ERROR() ) {
        my $error_code = $saferun->error_code() || 0;
        if ( !Cpanel::ExitValues::rsync->error_is_nonfatal_for_cpanel($error_code) ) {
            die Cpanel::Exception->create_raw( 'rsync streaming failed: ' . $saferun->autopsy() );
        }
        else {
            warn Cpanel::Exception->create_raw( 'A non-fatal error occurred during rsync streaming: ' . Cpanel::ExitValues::rsync->number_to_string($error_code) );
        }
    }

    return $rsync_parser->finish();

}
1;
