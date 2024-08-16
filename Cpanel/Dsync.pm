package Cpanel::Dsync;

# cpanel - Cpanel/Dsync.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A base class.
#----------------------------------------------------------------------

use strict;
use Cpanel::Dovecot::Utils            ();
use Cpanel::Parser::Dsync             ();
use Cpanel::Dovecot::Sync             ();
use Cpanel::SafeRun::Object           ();
use Cpanel::ExitValues::dsync         ();
use Cpanel::Exception                 ();
use Cpanel::CPAN::IO::Callback::Write ();

=pod

=encoding utf-8

=head1 NAME

Cpanel::Dsync - An interface to calling Dsync

=head1 SYNOPSIS

    use Cpanel::Dsync ();

    Cpanel::Dsync->run(
        'args'   => [
            '--force',
            '/source/dir/' => '/target/dir/',
        ]
    );

=cut

our $MAX_DSYNC_READ_WAIT_TIMEOUT = ( 60 * 180 );            # 180 minutes
our $TIMEOUT                     = ( 60 * 60 * 24 * 3 );    # 3 Days

sub run {
    my ( $class, %OPTS ) = @_;

    my $args = $OPTS{'args'} or die Cpanel::Exception::create( 'MissingParameter', [ name => 'args' ] );

    my $doveadm_bin  = Cpanel::Dovecot::Utils::doveadm_bin() or die Cpanel::Exception->create_raw("The system is missing the “doveadm” binary.");
    my $dsync_parser = Cpanel::Parser::Dsync->new();

    my $saferun = Cpanel::SafeRun::Object->new(
        'program'      => $doveadm_bin,
        'read_timeout' => $MAX_DSYNC_READ_WAIT_TIMEOUT,
        'timeout'      => $TIMEOUT,
        'args'         => [
            @Cpanel::Dovecot::Sync::DEFAULT_OPTIONS,
            @{$args},
        ],
        'stdout' => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                $dsync_parser->process_data(@_);
            }
        ),
        'stderr' => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                $dsync_parser->process_error_data(@_);
            }
        )
    );

    if ( $saferun->CHILD_ERROR() ) {
        my $error_code = $saferun->error_code() || 0;
        if ( !Cpanel::ExitValues::dsync->error_is_nonfatal_for_cpanel($error_code) ) {
            die Cpanel::Exception->create_raw( 'dsync streaming failed: ' . $saferun->autopsy() );
        }
    }

    return $dsync_parser->finish();

}
1;
