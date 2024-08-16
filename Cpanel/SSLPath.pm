package Cpanel::SSLPath;

# cpanel - Cpanel/SSLPath.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::PwCache ();
use Cpanel::Logger  ();

# First array element is default location
our @SSL_ROOTS = qw( /usr/share/ssl /etc/ssl /var/ssl /usr/local/ssl );
my $SYSTEM_DIR;

#for testing
sub _reset_system_dir_cache { $SYSTEM_DIR = undef }

# Returns scalar that is path to base directory for SSL certificates
# Depending upon arguments, either the user's directory or the system
# directory will be located.
sub get_base_dir {
    my ($user) = @_;

    # System lookup
    if ( !$user || $user eq 'root' ) {

        # Reuse previous lookup
        if ( defined $SYSTEM_DIR ) {
            return $SYSTEM_DIR;
        }

        # Check for first directory that exists
        foreach my $dir (@SSL_ROOTS) {
            if ( -d $dir ) {
                $SYSTEM_DIR = $dir;
                return $SYSTEM_DIR;
            }
        }

        # Return default directory
        if ( !$SYSTEM_DIR ) {
            $SYSTEM_DIR = $SSL_ROOTS[0];
            return $SYSTEM_DIR;
        }
    }

    # User lookup
    else {

        # always limited to EUID lookup home dir when not root
        if ( $> != 0 ) {
            if ($Cpanel::homedir) {
                return $Cpanel::homedir . '/ssl';
            }
            else {
                my $homedir = ( Cpanel::PwCache::getpwuid($>) )[7];
                if ( !$homedir ) {
                    my $logger = Cpanel::Logger->new();
                    $logger->warn("Failed to determine home directory for user ID $>");
                    return;
                }
                else {
                    return $homedir . '/ssl';
                }
            }
        }
        else {
            my $homedir = ( Cpanel::PwCache::getpwnam($user) )[7];
            if ( !$homedir ) {
                my $logger = Cpanel::Logger->new();
                $logger->warn("Failed to determine home directory for user $user");
                return;
            }
            else {
                return $homedir . '/ssl';
            }
        }
    }
}

sub getsslroot { goto &get_base_dir; }

sub check_dirs {
    my ($user) = @_;

    my $base_directory = get_base_dir($user);
    return if !$base_directory;

    my $logger = Cpanel::Logger->new();

    # Check base directory
    if ( -l $base_directory ) {    # Check for bad symlinked base directory
        my $link = readlink $base_directory;
        if ( $link eq '/usr' || $link eq '/usr/' || $link eq '.' ) {
            $logger->warn("Repairing bad SSL directory symlink, was $base_directory -> $link");
            unlink $base_directory;
        }
        elsif ( $user && $user ne 'root' ) {    # Don't allow users to have symlinked base directories
            $logger->warn("Removing symlinked $base_directory for security purposes, was $base_directory -> $link");
            unlink $base_directory;
        }
    }

    if ( !-e $base_directory ) {
        mkdir $base_directory, 0755;
        if ( !-d $base_directory ) {
            $logger->warn("Failed to create $base_directory: $!");
            return;
        }
    }
    elsif ( !-d _ ) {
        $logger->warn("SSL base directory $base_directory is not a directory");
        return;
    }
    else {
        chmod 0755, $base_directory;
    }

    # Check private directory
    if ( $user && $user ne 'root' && -l $base_directory . '/private' ) {    # Don't allow users to have symlinked private directories
        my $link = readlink $base_directory . '/private';
        $logger->warn("Removing symlinked '$base_directory/private' for security purposes, was $base_directory -> $link");
        unlink $base_directory . '/private';
    }

    if ( !-e $base_directory . '/private' ) {
        mkdir $base_directory . '/private', 0700;
        if ( !-d $base_directory . '/private' ) {
            $logger->warn("Failed to create $base_directory/private: $!");
            return;
        }
    }
    elsif ( !-d _ ) {
        $logger->warn("SSL private directory $base_directory/private is not a directory");
        return;
    }
    else {
        chmod 0700, $base_directory . '/private';
    }

    # Check certificate directory
    if ( $user && $user ne 'root' && -l $base_directory . '/certs' ) {    # Don't allow users to have symlinked certs directories
        my $link = readlink $base_directory . '/certs';
        $logger->warn("Removing symlinked '$base_directory/certs' for security purposes, was $base_directory -> $link");
        unlink $base_directory . '/certs';
    }

    if ( !-e $base_directory . '/certs' ) {
        mkdir $base_directory . '/certs', 0755;
        if ( !-d $base_directory . '/certs' ) {
            $logger->warn("Failed to create $base_directory/certs: $!");
            return;
        }
    }
    elsif ( !-d _ ) {
        $logger->warn("SSL certs directory $base_directory/certs is not a directory");
        return;
    }
    else {
        chmod 0755, $base_directory . '/certs';
    }

    return $base_directory;
}

1;
