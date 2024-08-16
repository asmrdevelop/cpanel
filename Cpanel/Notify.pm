package Cpanel::Notify;

# cpanel - Cpanel/Notify.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Set                          ();
use Cpanel::Fcntl                        ();
use Cpanel::SafeFile                     ();
use Cpanel::LoadModule                   ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Exception                    ();
use Cpanel::Debug                        ();

our $VERSION = '1.8';

my $DEFAULT_CONTENT_TYPE = 'text/plain; charset=utf-8';
our $NOTIFY_INTERVAL_STORAGE_DIR = '/var/cpanel/notifications';

#named args:
#   application - same as notification()
#   interval    - same as notification()
#   status      - same as notification()
#
#   class (string)
#   constructor_args (arrayref)
#
sub notification_class {
    my (%args) = @_;

    # interval is not required and will default to always sending the notification if not set
    if ( !defined $args{'interval'} ) {
        $args{'interval'} = 1;
    }

    if ( !defined $args{'status'} ) {
        $args{'status'} = 'No status set';
    }

    foreach my $param (qw(application status class constructor_args)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $param ] ) if !defined $args{$param};
    }

    if ( my @unwelcome_params = Cpanel::Set::difference( [ keys %args ], [qw(application status class constructor_args interval)] ) ) {
        die Cpanel::Exception::create_raw(
            'InvalidParameters',
            "The following parameters don't belong as an argument to notification_class(); you may have meant to pass these in constructor_args instead: " . join( ' ', @unwelcome_params )
        );
    }

    my $constructor_args = { @{ $args{'constructor_args'} } };

    # Not sending, we must return an object instead as thats what the caller expects
    # because they may want to render a template.
    if ( $constructor_args->{'skip_send'} ) {
        my $class = "Cpanel::iContact::Class::$args{'class'}";
        Cpanel::LoadModule::load_perl_module($class);

        # When we converted all iContact notifications
        # to use Cpanel::Notify we did not account for the
        # ones that use skip_send and call ->send on the
        # class later.  This code is a workaround to
        # resolve this problem.
        #
        # TODO: refactor this into a new sub called
        # get_notification_class_without_sending
        # or something similar
        #
        return $class->new(%$constructor_args);
    }

    return _notification_backend(
        $args{'application'},
        $args{'status'},
        $args{'interval'},
        sub {
            my $class = "Cpanel::iContact::Class::$args{'class'}";
            Cpanel::LoadModule::load_perl_module($class);
            return $class->new(%$constructor_args);
        },
    );
}

#TODO: Describe what each of these arguments does. (This documentation
#postdates the code itself significantly.)
#
#Named args:
#   application (AKA "app")     (optional) defaults to "Notice"
#   status                      text, required EXCEPT when interval <= 1
#   interval                    (optional) whole number, defaults to 0
#   msgheader (AKA "subject")   (optional) passed to iContact::icontact as "subject"
#   priority                    (optional) passed to iContact::icontact as "level"
#
#   The following are passed unaltered to iContact::icontact:
#       from
#       to
#       message
#       plaintext_message
#       content-type
#       attach_files
#
sub notification {
    my %AGS = @_;

    my $app = $AGS{'app'} || $AGS{'application'} || 'Notice';

    return _notification_backend(
        $app,
        $AGS{'status'},
        $AGS{'interval'} || 0,
        sub {
            my $module = "Cpanel::iContact";
            Cpanel::LoadModule::load_perl_module($module);

            my $from              = $AGS{'from'};
            my $to                = $AGS{'to'};
            my $msgheader         = $AGS{'msgheader'} || $AGS{'subject'};
            my $message           = $AGS{'message'};
            my $plaintext_message = $AGS{'plaintext_message'};
            my $priority          = $AGS{'priority'}     || 3;
            my $attach_files      = $AGS{'attach_files'} || [];

            #This actually serves no purpose except to satisfy unit tests;
            #icontact() actually puts in the safe default content type.
            my $content_type = $AGS{'content-type'} || $DEFAULT_CONTENT_TYPE;

            "$module"->can('icontact')->(
                'attach_files'      => $attach_files,
                'application'       => $app,
                'level'             => $priority,
                'from'              => $from,
                'to'                => $to,
                'subject'           => $msgheader,
                'message'           => $message,
                'plaintext_message' => $plaintext_message,
                'content-type'      => $content_type,
            );
        }
    );
}

sub _notification_backend {
    my ( $app, $status, $interval, $todo_cr ) = @_;

    my $is_ready = _checkstatusinterval(
        'app'      => $app,
        'status'   => $status,
        'interval' => $interval,
    );

    if ($is_ready) {
        return $todo_cr->();
    }
    elsif ( $Cpanel::Debug::level > 3 ) {
        Cpanel::Debug::log_warn("not sending notify app=[$app] status=[$status] interval=[$interval]");
    }

    return $is_ready ? 1 : 0;
}

sub notify_blocked {
    my %AGS      = @_;
    my $app      = $AGS{'app'};
    my $status   = $AGS{'status'};
    my $interval = $AGS{'interval'};

    return 0 if $interval <= 1;    # Special Case (ignore interval check);

    $app    =~ s{/}{_}g;           # Its possible to have slashes in the app name
    $status =~ s{:}{_}g;           # Its possible to have colons in the status

    my $db_file = "$NOTIFY_INTERVAL_STORAGE_DIR/$app";

    return 0 if !-e $db_file;

    my %notifications;
    my $notify_db_fh;
    if (
        my $nlock = Cpanel::SafeFile::safesysopen(
            $notify_db_fh, $db_file, Cpanel::Fcntl::or_flags('O_RDONLY'),
            0600
        )
    ) {
        local $/;
        %notifications = map { ( split( /:/, $_, 2 ) )[ 0, 1 ] } split( m{\n}, readline($notify_db_fh) );
        Cpanel::SafeFile::safeclose( $notify_db_fh, $nlock );
    }
    else {
        Cpanel::Debug::log_warn("Could not open $db_file: $!");
        return;
    }

    # Too soon to send
    if ( $notifications{$status} && ( ( $notifications{$status} + $interval ) > time() ) ) {
        return 1;
    }

    return 0;
}

{
    no warnings 'once';
    *update_notification_time_if_interval_reached = \&_checkstatusinterval;
}

# This not only checks the interval for the app/status to see if a notification
# is ready to be sent, it also sets the last time one was sent to now
sub _checkstatusinterval {
    my %AGS      = @_;
    my $app      = $AGS{'app'};
    my $status   = $AGS{'status'};
    my $interval = $AGS{'interval'};

    return 1 if $interval <= 1;    # Special Case (ignore interval check);

    $app    =~ s{/}{_}g;           # Its possible to have slashes in the app name
    $status =~ s{:}{_}g;           # Its possible to have colons in the status
    Cpanel::Validate::FilesystemNodeName::validate_or_die($app);

    my $notify = 0;

    if ( !-e $NOTIFY_INTERVAL_STORAGE_DIR ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::SafeDir::MK::safemkdir( $NOTIFY_INTERVAL_STORAGE_DIR, '0700' );
        if ( !-d $NOTIFY_INTERVAL_STORAGE_DIR ) {
            Cpanel::Debug::log_warn("Failed to setup notifications directory: $NOTIFY_INTERVAL_STORAGE_DIR: $!");
            return;
        }
    }

    my %notifications;
    my $notify_db_fh;
    my $db_file = "$NOTIFY_INTERVAL_STORAGE_DIR/$app";
    if ( my $nlock = Cpanel::SafeFile::safesysopen( $notify_db_fh, $db_file, Cpanel::Fcntl::or_flags(qw( O_RDWR O_CREAT )), 0600 ) ) {
        local $/;
        %notifications = map { ( split( /:/, $_, 2 ) )[ 0, 1 ] } split( m{\n}, readline($notify_db_fh) );
        if ( !exists $notifications{$status} || ( int( $notifications{$status} ) + int($interval) ) < time() ) {
            $notifications{$status} = time;
            $notify = 1;
        }
        seek( $notify_db_fh, 0, 0 );
        print {$notify_db_fh} join( "\n", map { $_ . ':' . $notifications{$_} } sort keys %notifications );
        truncate( $notify_db_fh, tell($notify_db_fh) );
        Cpanel::SafeFile::safeclose( $notify_db_fh, $nlock );
    }
    else {
        Cpanel::Debug::log_warn("Could not open $db_file: $!");
        return;
    }

    return $notify;
}

1;
