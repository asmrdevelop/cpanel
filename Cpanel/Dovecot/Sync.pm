package Cpanel::Dovecot::Sync;

# cpanel - Cpanel/Dovecot/Sync.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::SafeRun::Object ();
use Cpanel::Dovecot::Utils  ();
use Cpanel::Dovecot::Config ();
use Cpanel::Email::Mailbox  ();
use Cpanel::Exception       ();

our $MAX_ATTEMPTS = 10;

our %KNOWN_SYNC_TYPES = (
    'mirror' => 1,
    'backup' => 1,
);

our @DEFAULT_EXCLUDES = (
    '-x', 'INBOX..*',    # old cruft and .DS_Store like files
    '-x', '*@*_*',       # symlinked accounts

);

our @DEFAULT_OPTIONS = (
    '-o', "maildir_broken_filename_sizes=yes",
);

=pod

=head1 NAME

Cpanel::Dovecot::Sync

=head1 DESCRIPTION

This module is provides an interface to dsync multiple
times until a successful sync is achieved.

It will attempt to resync mailboxes if the sync has
failed multiple times.

Its primary goal is to abstract away the process of getting
a mailbox to successfully sync from a source to a target
by account for dovecot restarts, corruption or other system events.

=head1 SYNOPSIS

      Cpanel::Dovecot::Sync::dsync_until_status_zero(
          'email_account'  => $user,
          'source_format'  => 'detect',
          'source_maildir' => "$homedir/mail",
          'target_format'  => 'detect',
          'target_maildir' => "$homedir/mail",
          'sync_type'      => 'mirror',
          'disable_fsync'  => 1,
          'verbose'        => 0,
      ),

=cut

=head1 METHODS

=head2 dsync_until_status_zero

Call dovecot's dsync up to ten times until it returns
a status of zero (success) while attempting to recover
from any sync failures.

On the 5th attempt this function will force a mailbox
resync in the hope that a zero status can be achieved
on an subsequent attempt.

=head3 Arguments

email_account  - The email account to operate on

source_maildir - The directory that email is stored in

source_format  - The format of the mail in the source_maildir (mbox, mdbox, maildir, or detect for auto-detection)

source_options - An array reference or hash reference which specifies optional handling parameters for the source mailbox

target_maildir - The directory that email should be synced to

target_format  - The format of the mail in the target_maildir (mbox, mdbox, maildir, or detect for auto-detection)

target_options - An array reference or hash reference which specifies optional handling parameters for the target mailbox

sync_type      - The direction of the sync
                    mirror - a 2-way sync that will get the source and target in the same state
                    backup - a 1-way sync that will get the target in the same state as source

disable_fsync  - This will disable calling fsync to ensure the data is written to the disk
                  * This option should only be used if you plan to call dsync multiple times
                    with the final call not enabling this option *

verbose        - Prints messages about what is happening

=head3 Return Value

The number times dsync was called to achieve a status of zero

=cut

sub dsync_until_status_zero {
    my (%OPTS) = @_;
    my $run;

    foreach my $required (qw(email_account source_format target_format source_maildir target_maildir sync_type disable_fsync verbose)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !length $OPTS{$required};
    }

    foreach my $optional (qw(source_options target_options)) {
        $OPTS{$optional} //= {};
        if ( ref( $OPTS{$optional} ) eq 'ARRAY' ) {
            my $params_hr = {};
            foreach my $key ( @{ $OPTS{$optional} } ) {
                $params_hr->{$key} = undef;
            }
            $OPTS{$optional} = $params_hr;
        }
        elsif ( ref( $OPTS{$optional} ) ne 'HASH' ) {    # We didn't get anything we expected
            die Cpanel::Exception::create_raw( 'InvalidParameter', "The “$optional” parameter must be an arrayref or hashref if it exists" );
        }
    }

    foreach my $format (qw(source_format target_format)) {
        if ( !$Cpanel::Dovecot::Config::KNOWN_FORMATS{ $OPTS{$format} } ) {
            die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be one of the following: [join,~, ,_2]", [ $format, [ sort keys %Cpanel::Dovecot::Config::KNOWN_FORMATS ] ] );
        }
    }
    if ( !$KNOWN_SYNC_TYPES{ $OPTS{'sync_type'} } ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be one of the following: [join,~, ,_2]", [ 'sync_type', [ sort keys %KNOWN_SYNC_TYPES ] ] );
    }

    if ( $OPTS{'source_format'} eq 'detect' ) {
        $OPTS{'source_format'} = Cpanel::Email::Mailbox::detect_format( $OPTS{'source_maildir'} );
    }
    if ( $OPTS{'target_format'} eq 'detect' ) {

        # If the source format is maildir we are likely going to convert to mdbox
        # otherwise we assume they want our default format (maildir)
        $OPTS{'target_format'} = $OPTS{'source_format'} eq 'maildir' ? 'mdbox' : 'maildir';
    }

    for my $attempt ( 1 .. $MAX_ATTEMPTS ) {
        print "Syncing “$OPTS{'email_account'}” $OPTS{'source_format'} -> $OPTS{'target_format'} (Attempt: $attempt/$MAX_ATTEMPTS)\n" if $OPTS{'verbose'};
        if ( $attempt == 5 ) {
            print "Attempting to repair “$OPTS{'email_account'}” $OPTS{'source_format'}\n" if $OPTS{'verbose'};
            Cpanel::Dovecot::Utils::force_resync( $OPTS{'email_account'} );
        }

        my @args      = _construct_dsync_args( \%OPTS, $attempt );
        my $dsync_bin = Cpanel::Dovecot::Utils::dsync_bin();
        print "For those of you playing at home, here's what we're about to run in order to convert the mailbox:\n    $dsync_bin " . join( " ", @args ) if $OPTS{'verbose'};

        $run = Cpanel::SafeRun::Object->new(
            program      => $dsync_bin,
            timeout      => 86400,
            read_timeout => 86400,
            args         => \@args,
        );
        print $run->stdout() if $OPTS{'verbose'};
        return $attempt      if !$run->CHILD_ERROR();
        my $error = $run->stderr() || '';
        if ( length $error ) {
            if ( $error =~ m/want to run dsync again/ ) {

                # We ignore this since it's pretty much expected
            }
            else {
                warn $error if length $error;
            }
        }

        # Sleep for a bit to allow for a dovecot restart if its offline
        if ( $run->error_code() ) {
            if ( $run->error_code() == $Cpanel::Dovecot::DOVEADM_EX_NOUSER ) {
                last;
            }
            elsif ( $run->error_code() == $Cpanel::Dovecot::DOVEADM_EX_TEMPFAIL ) {
                last if $attempt == $MAX_ATTEMPTS;
                sleep(30);
                next;
            }
            elsif ( $run->error_code() == $Cpanel::Dovecot::DOVEADM_EX_OKBUTDOAGAIN ) {

                # https://doc.dovecot.org/admin_manual/error_codes/
                # Success, but needs another run to finalize..
                last if $attempt == $MAX_ATTEMPTS;
                sleep(3);
                next;
            }
            else {
                warn $run->autopsy();
            }
        }
    }

    $run->die_if_error();

    die sprintf( "UNEXPECTED FAILURE TO THROW! (%s)", $run->autopsy() );
}

sub _construct_dsync_args {
    my ( $opts_hr, $attempt ) = @_;
    die Cpanel::Exception::create_raw( 'InvalidParameter', "First argument is not a hashref" ) unless ref $opts_hr eq 'HASH';
    my (%OPTS) = %$opts_hr;

    return (
        ( $attempt == $MAX_ATTEMPTS ? ('-D')                       : () ),
        ( $OPTS{'disable_fsync'}    ? ( '-o', 'mail_fsync=never' ) : () ),
        @DEFAULT_OPTIONS,
        '-o', 'mailbox_list_index=no',
        '-o', "mail_location=$OPTS{'target_format'}:$OPTS{'target_maildir'}" . _stringify_mail_location_options( $OPTS{'target_options'} ),
        '-u', $OPTS{'email_account'},
        '-v', $OPTS{'sync_type'},
        @DEFAULT_EXCLUDES,
        "$OPTS{'source_format'}:$OPTS{'source_maildir'}" . _stringify_mail_location_options( $OPTS{'source_options'} )
    );
}

sub _stringify_mail_location_options {
    my (%OPTS) = %{ $_[0] };
    my $retstr = join( ':', map { defined( $OPTS{$_} ) ? "$_=$OPTS{$_}" : $_ } keys %OPTS );
    return ( length($retstr) ? ":$retstr" : '' );
}

1;
