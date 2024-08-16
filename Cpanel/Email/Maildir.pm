package Cpanel::Email::Maildir;

# cpanel - Cpanel/Email/Maildir.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Debug                        ();
use Cpanel::SV                           ();

our $ONE_MEBIBYTE = 1048576;

our $MAX_EMAIL_QUOTA_64BIT = 1024 * 4194304 * $ONE_MEBIBYTE;    # 4 PiB, the maximum size that doesn't appear to cause any problems with dovecot
our $MAX_EMAIL_QUOTA_32BIT = 2048 * $ONE_MEBIBYTE;              # 2 GiB, the maximum signed size of a 32bit int.

our $DEFAULT_EMAIL_QUOTA_64BIT = 32768 * $ONE_MEBIBYTE;         # 32 GiB, the average size the industry is offering as of late 2014
our $DEFAULT_EMAIL_QUOTA_32BIT = 1024 * $ONE_MEBIBYTE;          # 1 GiB, half the maximum on 32 bit (increased from the age old 256 MiB after 11 years)

sub get_max_email_quota_mib {
    return ( get_max_email_quota() / $ONE_MEBIBYTE );
}

sub get_max_email_quota {
    return $MAX_EMAIL_QUOTA_64BIT;
}

sub get_default_email_quota_mib {
    return ( get_default_email_quota() / $ONE_MEBIBYTE );
}

sub get_default_email_quota {
    return $DEFAULT_EMAIL_QUOTA_64BIT;
}

sub _find_maildirsize_file {
    my ( $email, $domain, $homedir ) = @_;
    return if !defined $email || !$domain;

    $homedir ||= $Cpanel::homedir;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($email);
    Cpanel::Validate::FilesystemNodeName::validate_or_die($domain);

    if ( index( $email, '@' ) > -1 || index( $domain, '@' ) > -1 || index( $domain, '.' ) == -1 ) {
        Cpanel::Debug::log_warn("Unable to lookup maildirsize file for $email\@$domain with homedir of $homedir. Invalid information.");
        return;
    }
    else {
        Cpanel::SV::untaint($_) foreach ( $domain, $email );
    }

    return (
        $email eq '_archive'
        ? "$homedir/mail/archive/$domain/maildirsize"
        : "$homedir/mail/$domain/$email/maildirsize"
    );
}

sub set_maildirsize_quota {
    my ( $email, $domain, $quota, $quiet ) = @_;
    ## NOTE: System account mail quotas are not supported, only POP accounts. Domain required.

    return if $Cpanel::CPDATA{'DEMO'};
    return if !defined $email || !$domain;

    if ( !$quota || $quota =~ m/unlimited/i || int $quota > get_max_email_quota_mib() ) {
        $quota = 0;
    }
    if ( int $quota > 0 ) {
        $quota = get_quota_in_bytes_from_mib($quota);
    }
    else {
        $quota = 0;
    }

    my $maildirsize_file = _find_maildirsize_file( $email, $domain );
    if ( !$maildirsize_file ) {
        Cpanel::Debug::log_warn("Failed to determine location of maildirsize file for $email\@$domain");
        my $msg = "Unable to determine location of maildirsize file!";
        print $msg if !$quiet;
        return 0, $msg;
    }

    require Cpanel::SafeFile;
    if ( !-e $maildirsize_file ) {
        my $orig_umask  = umask(0077);
        my $mdsize_lock = Cpanel::SafeFile::safeopen( \*MDSIZE, '>', $maildirsize_file );
        if ( !$mdsize_lock ) {
            Cpanel::Debug::log_warn("Failed to update maildirsize file for $email\@$domain. Unable to safely open file $maildirsize_file: $!");
            umask($orig_umask);
            my $msg = "Unable to safely open file: $!\n";
            print $msg if !$quiet;
            return 0, $msg;
        }
        my $quota_line = sprintf( "%.0f", $quota ) . "S,0C\n";
        print MDSIZE $quota_line or die "Unable to update maildirsize file: $!";    # Leaving lock
        Cpanel::SafeFile::safeclose( \*MDSIZE, $mdsize_lock );
        umask($orig_umask);
        return 1;
    }
    else {
        my $mdsize_lock = Cpanel::SafeFile::safeopen( \*MDSIZE, '+<', $maildirsize_file );
        if ( !$mdsize_lock ) {
            Cpanel::Debug::log_warn("Failed to update maildirsize file for $email\@$domain. Unable to safely open file $maildirsize_file: $!");
            my $msg = "Unable to safely open file: $!\n";
            print $msg if !$quiet;
            return 0, $msg;
        }
        if ( $> != 0 ) {
            chmod 0600, $maildirsize_file;
        }

        my $quota_line = <MDSIZE>;

        # The count portion of the quota is irrelevant as we do not provide a means of setting it.
        # generate_maildirsize also sets the C value to 0, doing the same here for consistency
        $quota_line = sprintf( "%.0f", $quota ) . "S,0C\n";
        my @sizes = <MDSIZE>;
        seek MDSIZE, 0, 0 or die "Unable to update maildirsize file: $!";                   # Leaving lock
        print MDSIZE $quota_line         or die "Unable to update maildirsize file: $!";    # Leaving lock
        print MDSIZE join( '', @sizes )  or die "Unable to update maildirsize file: $!";    # Leaving lock
        truncate( MDSIZE, tell(MDSIZE) ) or die "Unable to update maildirsize file: $!";    # Leaving lock

        Cpanel::SafeFile::safeclose( \*MDSIZE, $mdsize_lock );
        return 1;
    }
}

# Will return a negitive value if the quota is larger
# the maximum permitted
# Note: this returns 1 less then the maximum because the ACTUAL
# maximum with bugs is one byte less
sub get_quota_in_bytes_from_mib {
    my ($quota) = @_;
    return ( ( int $quota ) * $ONE_MEBIBYTE ) - ( ( int $quota ) == get_max_email_quota_mib() ? 1 : 0 );
}

1;
