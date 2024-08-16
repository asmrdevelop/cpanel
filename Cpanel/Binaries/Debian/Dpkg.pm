package Cpanel::Binaries::Debian::Dpkg;

# cpanel - Cpanel/Binaries/Debian/Dpkg.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Binaries::Debian::Dpkg

=head1 DESCRIPTION

Interface to common dpkg commands.

=head1 WARNING

    ***************************************************************
    * DO NOT USE this in any new code! Prefer Cpanel::Pkgr instead!
    ****************************************************************

=head1 SYNOPSIS

    my $dpkg = Cpanel::Binaries::Debian::Dpkg->new;
    $dpkg->what_owns('file1')
    ...

=cut

use cPstrict;

use parent 'Cpanel::Binaries::Role::Debian';

=head1 METHODS

=head2 bin_path ($self)

Provides the binary our parent SafeRunner should use.

=cut

sub bin_path ($self) {
    return '/usr/bin/dpkg';
}

=head2 needs_lock

Allow exceptions to some calls that don't actually need exclusivity even if an (un)install is happening.

=cut

sub needs_lock ( $self, $action, @args ) {
    return 1 if grep { $action eq $_ } qw/-i -P -r/;
    return 0;
}

=head2 what_owns ($self, $file)

Reports what package owns a file. returns undef if it cannot be determined.

Because of debian convering things from /bin to /usr/bin, we have to fall back.

=cut

sub what_owns ( $self, $file ) {
    return unless length $file;
    return unless $file =~ m{^/};

    my $r = $self->cmd( '-S', $file );
    if (   $r->{'status'}
        && $file !~ m{^/usr/local/cpanel}
        && $file =~ s{^/usr/}{/} ) {

        # Try /bin/foo if /usr/bin/foo fails. debian does strange things with its packages.
        # note: this is more than /usr/bin
        $r = $self->cmd( '-S', $file );
    }

    return if $r->{'status'};

    my $package = $r->{'output'} // '';
    $package =~ s/:.+//ms;    # passwd: /usr/bin/passwd
    return $package;
}

=head2 what_owns_files_no_errors ($self, @files)

Reports what packages owns a list of file.
Ignore files not owned by a package.

=cut

sub what_owns_files_no_errors ( $self, @files ) {
    @files = grep { length $_ && m{^/} } @files;    # Strip files without a leading slash you can't query on that.
    return unless scalar @files;

    # return { output => $out, status => $? };
    # cannot check status code as we are ignoring errors
    #   when requesting files not owned
    my $r = $self->cmd( '-S', @files ) // {};

    my @lines = split "\n", $r->{'output'} // '';

    my %packages;

    foreach my $l (@lines) {
        next if $l =~ m{^dpkg-query: no path found};
        next if $l =~ m{^diversion by };

        if ( $l =~ qr/^([^:]+):/ ) {
            my $pkg = $1;
            $packages{$pkg} //= 1;
        }
    }

    return unless keys %packages;

    return [ sort keys %packages ];
}

=head2 installed_packages ($self)

returns a hash of all packages installed on the local system.

=cut

sub installed_packages ($self) {
    my $installed = $self->cmd( '--list', '--no-pager' );
    $installed->{'status'} and die sprintf( "Error (%s) running %s: %s", $installed->{'status'} >> 8, $self->bin, $installed->{'output'} );

    my @lines = split( "\n", $installed->{'output'} // '' );

    # Strip off all of the header lines.
    shift @lines while ( @lines && $lines[0] !~ m/^\Q+++-=====\E/ );
    shift @lines;    # Strip off the last header line.

    my %results;
    foreach my $line (@lines) {
        my $attributes = substr( $line, 0, 3 );
        my ( $package, $ver_release, $arch, $description ) = split( " ", substr( $line, 3 ), 4 );
        $results{$package} = {
            ver_rel     => $ver_release,
            arch        => $arch,
            description => $description,
            _parse_attributes($attributes),
        };
    }

    return \%results;
}

# https://www.halolinux.us/debian-system-concepts/interacting-with-the-package-database.html
sub _parse_attributes ($attr) {
    length $attr == 3 or die("Unexpected length of attributes");
    my ( $user, $state, $error ) = split( "", $attr );

    $error =~ s/\s+//;    # Strip spaces from this field as the norm is for it to be empty.
    return ( user_requested => $user, current_state => $state, package_errors => $error );
}

# dpkg -S $file
sub whatprovides ( $self, $filename ) {
    my @args = ( '-S', $filename );
    my $out  = $self->cmd(@args);
    return if $out->{'status'};
    return substr( $out->{'output'}, 0, index( $out->{'output'}, ':' ) );
}

1;
