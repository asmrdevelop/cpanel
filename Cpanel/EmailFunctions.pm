package Cpanel::EmailFunctions;

# cpanel - Cpanel/EmailFunctions.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeFile     ();
use Cpanel::Fcntl        ();
use Cpanel::LoadFile     ();
use Cpanel::Email::Utils ();
use Cpanel::Autodie      ();
use IO::Handle           ();

our $VERSION = '0.1.1';

sub getaliasesfromfile {
    my $file        = shift || die "getaliasesfromfile requires a file";
    my $aliases_ref = {};

    my $file_fh;
    if ( -e $file && Cpanel::Autodie::open( $file_fh, '<', $file ) ) {
        $aliases_ref = _read_aliases_from_fh($file_fh);
        Cpanel::Autodie::close( $file_fh, $file );
    }
    return wantarray ? %{$aliases_ref} : $aliases_ref;
}

sub changealiasinfile {
    my $username = shift || return;
    my $forward  = shift || '';
    my $file     = shift || return;
    return if ( !-e $file || !-w _ );

    my $alias_fh  = IO::Handle->new();
    my $aliaslock = Cpanel::SafeFile::safesysopen( $alias_fh, $file, Cpanel::Fcntl::or_flags(qw( O_RDWR O_CREAT )) );
    if ( !$aliaslock ) {
        warn "Could not write to $file: $!\n";
        return;
    }

    my $aliasfile_ref = _read_aliases_from_fh($alias_fh);

    # Update alias hash with new value
    if ( $forward eq '' ) {
        if ( exists $aliasfile_ref->{$username} ) {
            delete $aliasfile_ref->{$username};
        }
        else {
            Cpanel::SafeFile::safeclose( $alias_fh, $aliaslock );

            # Doesn't exist so nothing to do.
            return;
        }
    }
    else {
        $aliasfile_ref->{$username} = scalar Cpanel::Email::Utils::get_forwarders_from_string($forward);
    }

    seek( $alias_fh, 0, 0 );
    foreach my $alias ( sort keys %{$aliasfile_ref} ) {
        print {$alias_fh} $alias . ': ' . join( ",", map { Cpanel::Email::Utils::normalize_forwarder_quoting($_) } @{ $aliasfile_ref->{$alias} } ) . "\n";
    }
    truncate( $alias_fh, tell($alias_fh) );
    Cpanel::SafeFile::safeclose( $alias_fh, $aliaslock );

    return 1;
}

sub getemailaddressfromfile {
    my $file = shift || die "getemailaddressfromfile requires a file";

    my @destinations = ();
    my $contents     = Cpanel::LoadFile::load($file);
    foreach my $line ( split( m{\n}, $contents ) ) {
        push @destinations, Cpanel::Email::Utils::get_forwarders_from_string($line);
    }

    return @destinations;
}

sub unquote_email_destination {
    my ($destination) = @_;
    chomp $destination;
    $destination =~ s{ (?: \A ["'] | ["'] \z) }{}xmsg;
    return $destination;
}

sub _read_aliases_from_fh {
    my ($file_fh) = @_;

    my %aliases;
    while ( my $line = readline($file_fh) ) {
        chomp $line;
        my ( $user, $forward, $badval ) = split m{ \s* [;:] \s* }xms, $line, 3;
        next if ( $badval || !length $user || !length $forward );
        $aliases{$user} = scalar Cpanel::Email::Utils::get_forwarders_from_string($forward);
    }
    return \%aliases;
}

1;

__END__

=head1 NAME

Cpanel::EmailFunctions - Small collection of Email related functions

=head1 SYNOPSIS

    use Cpanel::EmailFunctions;
    my @addresses = getemailaddressfromfile($homedir . '/.contactemail');
