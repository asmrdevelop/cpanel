package Cpanel::Update::Logger;

# cpanel - Cpanel/Update/Logger.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::SafeDir::MK        ();
use Cpanel::Time::Local        ();
use Cpanel::FHUtils::Autoflush ();
use File::Basename             ();

# Converted to constant to make perlcritic happy
use constant {
    DEBUG => 0,
    INFO  => 25,
    WARN  => 50,
    ERROR => 75,
    FATAL => 100,
};

our $VERSION = '1.2';

# For testing:
our $_BACKLOG_TIE_CLASS;

sub new {
    my $class = shift;
    my $self  = shift || {};
    ref($self) eq 'HASH' or CORE::die("hashref not passed to new");

    bless( $self, $class );

    # Set STDOUT behavior (default yes)
    $self->{'stdout'} = 1 if ( !defined $self->{'stdout'} );

    # Set TIMESTAMP PRINTING behavior (default yes)
    $self->{'timestamp'} = 1 if ( !defined $self->{'timestamp'} );

    # Setup an empty array if we are asked to keep track of messages via 'to_memory'
    if ( $self->{'to_memory'} ) {
        $self->{'backlog'} = [];

        tie @{ $self->{'backlog'} }, $_BACKLOG_TIE_CLASS if $_BACKLOG_TIE_CLASS;
    }

    eval { $self->set_logging_level( $self->{'log_level'} ); 1 }
      or CORE::die("An invalid logging level was passed to new: $self->{'log_level'}");

    $self->open_log() if $self->{'logfile'};

    # If a pbar was passed in, we'll set the pbar as we go.
    if ( exists $self->{'pbar'} and defined $self->{'pbar'} ) {
        $self->{'pbar'} += 0;
        $self->update_pbar( $self->{'pbar'} );
    }

    return $self;
}

sub open_log {
    my $self = shift or CORE::die();

    my $log_file    = $self->{'logfile'};
    my $logfile_dir = File::Basename::dirname($log_file);
    my $created_dir = 0;
    if ( !-d $logfile_dir ) {
        Cpanel::SafeDir::MK::safemkdir( $logfile_dir, '0700', 2 );
        $created_dir = 1;
    }

    my $old_umask = umask(0077);    # Case 92381: Logs should not be world-readable
    open( my $fh, '>>', $log_file ) or do {
        CORE::die("Failed to open '$log_file' for append: $!");
    };

    umask($old_umask);

    Cpanel::FHUtils::Autoflush::enable($fh);
    Cpanel::FHUtils::Autoflush::enable( \*STDOUT ) if $self->{'stdout'};

    $self->{'fh'} = $fh;

    unless ( $self->{brief} ) {
        print {$fh} '-' x 100 . "\n";
        print {$fh} "=> Log opened from $0 ($$) at " . localtime(time) . "\n";
    }

    $self->warning("Had to create directory $logfile_dir before opening log") if ($created_dir);

    return;
}

sub close_log {
    my $self = shift or CORE::die();

    return if ( !$self->{'fh'} );
    my $fh = $self->{'fh'};

    unless ( $self->{brief} ) {
        print {$fh} "=> Log closed " . localtime(time) . "\n";
    }

    warn("Failed to close file handle for $self->{'logfile'}") if ( !close $fh );
    delete $self->{'fh'};

    return;
}

sub DESTROY {
    my $self = shift or CORE::die("DESTROY called without an object");
    $self->close_log if ( $self->{'fh'} );

    return;
}

sub log {
    my $self = shift         or CORE::die("log called as a class");
    ref $self eq __PACKAGE__ or CORE::die("log called as a class");

    my $msg = shift or return;

    # 2nd arg can say don't send to stdout, regardless of object settings.
    my $stdout = shift;
    $stdout = $self->{'stdout'} if ( !defined $stdout );

    my $to_memory = $self->{'to_memory'};
    my $fh        = $self->{'fh'};

    foreach my $line ( split( /[\r\n]+/, $msg ) ) {
        if ( $self->{'timestamp'} ) {
            substr( $line, 0, 0, '[' . Cpanel::Time::Local::localtime2timestamp() . '] ' );
        }

        chomp $line;
        print STDOUT "$line\n" if $stdout;
        print {$fh} "$line\n"  if $fh;
        push @{ $self->{'backlog'} }, "$line" if ($to_memory);
    }

    return;
}

sub _die {
    my $self    = shift or CORE::die();
    my $message = shift || '';

    $self->log("***** DIE: $message");
    return CORE::die( "exit level [die] [pid=$$] ($message) " . join ' ', caller() );
}

sub fatal {
    my $self = shift or CORE::die();
    return if ( $self->{'log_level_numeric'} > FATAL );

    my $message = shift || '';

    $self->log("***** FATAL: $message");
    $self->set_need_notify();

    return;
}

sub error {
    my $self = shift or CORE::die();
    return if ( $self->{'log_level_numeric'} > ERROR );

    my $message = shift || '';

    $self->log("E $message");

    return;
}

sub warning {
    my $self = shift or CORE::die();
    return if ( $self->{'log_level_numeric'} > WARN );

    my $message = shift || '';

    $self->log("W $message");

    return;
}

sub panic {
    my $self = shift or CORE::die();
    return if ( $self->{'log_level_numeric'} > ERROR );

    my $message = shift || '';

    $self->log("***** PANIC!");
    $self->log("E $message");
    $self->log("***** PANIC!");
    $self->set_need_notify();

    return;
}

sub info {
    my $self = shift or CORE::die();
    return if ( $self->{'log_level_numeric'} > INFO );

    my $message = shift || '';

    $self->log("  $message");

    return;
}

sub debug {
    my $self = shift or CORE::die();
    return if ( $self->{'log_level_numeric'} > DEBUG );

    my $message = shift || '';

    $self->log("D $message");

    return;
}

sub get_logging_level { return shift->{'log_level'} }

# Object method. Takes string of m/debug|info|warn|error|fatal/i or fails.
# Defaults to info if nothing is sent in.
sub set_logging_level {
    my $self = shift or CORE::die();

    my $log_level = shift;
    $log_level = 'info' if ( !defined $log_level );

    my $old_log_level = $self->get_logging_level();

    if ( $log_level =~ m/^fatal/i ) {
        $self->{'log_level'}         = 'fatal';
        $self->{'log_level_numeric'} = FATAL;
    }
    elsif ( $log_level =~ m/^error/i ) {
        $self->{'log_level'}         = 'error';
        $self->{'log_level_numeric'} = ERROR;
    }
    elsif ( $log_level =~ m/^warn/i ) {
        $self->{'log_level'}         = 'warning';
        $self->{'log_level_numeric'} = WARN;
    }
    elsif ( $log_level =~ m/^info/i ) {
        $self->{'log_level'}         = 'info';
        $self->{'log_level_numeric'} = INFO;
    }
    elsif ( $log_level =~ m/^debug/i ) {
        $self->{'log_level'}         = 'debug';
        $self->{'log_level_numeric'} = DEBUG;
    }
    else {
        CORE::die("Unknown logging level '$log_level' passed to set_logging_level");
    }

    return $old_log_level;
}

sub get_pbar { return shift->{'pbar'} }

sub increment_pbar {
    my $self = shift or CORE::die();
    return if ( !exists $self->{'pbar'} );

    my $amount    = shift || 1;
    my $new_value = $self->{'pbar'} + $amount;

    return $self->update_pbar($new_value);
}

sub update_pbar {
    my $self = shift or CORE::die();
    return if ( !exists $self->{'pbar'} );

    my $new_value = shift || 0;
    if ( $new_value > 100 ) {
        $self->debug("Pbar set to > 100 ($new_value)");
        $new_value = 100;
    }

    return if $new_value == $self->{'pbar'};
    $self->{'pbar'} = $new_value;

    $self->info( $new_value . '% complete' );

    return;
}

sub set_need_notify {
    my $self = shift;
    ref $self eq __PACKAGE__ or CORE::die("log called as a class");
    $self->info("The Administrator will be notified to review this output when this script completes");

    return $self->{'need_notify'} = 1;
}

sub get_need_notify {
    my $self = shift;
    ref $self eq __PACKAGE__ or CORE::die("log called as a class");
    return $self->{'need_notify'};
}

sub get_stored_log {
    my $self = shift;
    ref $self eq __PACKAGE__ or CORE::die("log called as a class");

    return if ( !$self->{'to_memory'} );

    #print STDERR Dumper( $$, (caller 0)[3], tied @{ $self->{'backlog'} } );
    return $self->{'backlog'};
}

sub get_next_log_message {
    my $self = shift;
    ref $self eq __PACKAGE__ or CORE::die("log called as a class");

    return if ( !$self->{'to_memory'} );

    #print STDERR Dumper( $$, (caller 0)[3], tied @{ $self->{'backlog'} } );
    return shift @{ $self->{'backlog'} };
}

# These functions are provided to make a Cpanel::Update::Logger
# and a Cpanel::Output object interchangeable in Cpanel::SysPkgs::YUM
# They are not in the *success = \&info; format as it breaks
# updatednow.static with this error: Name "Cpanel::Update::Logger::success" used only once: possible typo at ./updatenow.static
sub success { goto \&info; }
sub out     { goto \&info; }
sub warn    { goto \&warning; }
sub die     { goto \&_die; }

1;
