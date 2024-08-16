package Cpanel::BWFiles;

# cpanel - Cpanel/BWFiles.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Warnings for debug only
#use warnings;

use strict;

use Cpanel::ConfigFiles ();

my $bandwidth_directory = $Cpanel::ConfigFiles::BANDWIDTH_DIRECTORY;
my @types               = qw(http ftp smtp imap pop3);
my @all_types           = ( @types, 'all' );
my @sets                = qw(peak rate);

sub default_dir {
    return $bandwidth_directory;
}

sub all_types {
    return @all_types;
}

sub individual_types {
    return @types;
}

sub is_individual_type {
    return grep { $_[0] eq $_ } @types;
}

sub one_rrd_file {
    my ( $prefix, $type, $set, $dir ) = @_;
    $dir ||= default_dir();
    return "$dir/$prefix-$type-$set.rrd";
}

sub rrd_files {
    my ( $prefix, $dir ) = ( @_, default_dir() );
    my @files;
    foreach my $s (@sets) {
        push @files, "$dir/$prefix-$_-$s.rrd" for @all_types;
    }
    return @files;
}

sub remainder_file {
    my ( $prefix, $dir ) = ( @_, default_dir() );
    return "$dir/$prefix.remainder";
}

sub old_rrd_files {
    my ( $prefix, $dir ) = ( @_, default_dir() );
    return map { "$dir/$prefix-$_.rrd" } @all_types;
}

# Filename temporarily used during development. Just in case we need to find them.
sub old_devel_rrd_files {
    my ( $prefix, $dir ) = ( @_, default_dir() );
    return map { "$dir/$prefix-$_-bytecount.rrd" } @all_types;
}

sub all_new_and_old_bandwidth_related_files {
    my ( $prefix, $dir ) = @_;

    unless ( defined $dir ) {
        $dir = default_dir();
    }

    return (
        rrd_files( $prefix, $dir ),
        remainder_file( $prefix, $dir ),
        old_rrd_files( $prefix, $dir ),
    );
}

1;    # Magic true value required at end of module

__END__

=pod


=head1 NAME

Cpanel::BWFiles - Utilities for getting the Bandwidth RRDtool filenames

=head1 SYNOPSIS

    use Cpanel::BWFiles;

    my @bw_types = Cpanel::BWFiles::all_types();
    my $bw_dir = Cpanel::BWFiles::default_dir();

    my @domain_files = Cpanel::BWFiles::rrd_files( 'example.com' );
    my @user_files = Cpanel::BWFiles::rrd_files( 'fred' );

=head1 DESCRIPTION

This module factors out the logic for dealling with the individual files in the
Bandwidth subsystem, so that logic is not scattered throughout the system.

=head1 INTERFACE

=head2 Cpanel::BWFiles::default_dir()

Returns the default directory for the bandwidth files as a string.

=head2 Cpanel::BWFiles::all_types()

Returns a list of all of the bandwidth file types, including the 'all' summary
type.

=head2 Cpanel::BWFiles::individual_types()

Returns a list of all of the bandwidth file types, excluding the 'all' summary
type.

=head2 Cpanel::BWFiles::is_individual_type( $type )

Returns true if the supplied type is one of the individual bandwidth types.

=head2 Cpanel::BWFiles::one_rrd_file( $prefix, $type, $set [, $dir ] )

Build the name for a single bandwidth RRD file. This method expects all of the
pieces of the filename to be supplied.

The C<$prefix> is the user or domain for the file. The C<$type> is one of the
values returned by C<all_types>. The value of C<$set> is one of the defined
resolution sets: I<peak> or I<rate>.

The optional C<$dir> parameter specifies the directory for the file. If not
supplied the C<default_dir()> is used.

=head2 Cpanel::BWFiles::rrd_files( $prefix [, $dir ] )

Returns a list of the full paths for all bandwidth RRD files for the given
C<$prefix> (user or domain name).

If the optional C<$dir> parameter is supplied the filename are located in that
directory. If the C<$dir> parameter is not supplied, the default directory is
used instead.

This method just constructs the names, there is no check for whether or not the
files or directories exist.

=head2 Cpanel::BWFiles::remainder_file( $prefix [, $dir ] )

Return the name of the remainder file associated with the specified C<$prefix>.

If the optional C<$dir> parameter is supplied the filename are located in that
directory. If the C<$dir> parameter is not supplied, the default directory is
used instead.

=head2 Cpanel::BWFiles::old_rrd_files( $prefix [, $dir ] )

Returns a list of the full paths for all old bandwidth RRD files for the given
C<$prefix> (user or domain name).

If the optional C<$dir> parameter is supplied the filename are located in tht
directory. If the C<$dir> parameter is not supplied, the default directory is
used instead.

This method just constructs the names, there is no check for whether or not the
files or directories exist.

=head2 Cpanel::BWFiles::old_devel_rrd_files( $prefix [, $dir ] )

Returns a list of the full paths for an old development version of the
bandwidth RRD files for the given C<$prefix> (user or domain name).

If the optional C<$dir> parameter is supplied the filename are located in tht
directory. If the C<$dir> parameter is not supplied, the default directory is
used instead.

This method just constructs the names, there is no check for whether or not the
files or directories exist.

=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::BWFiles requires no configuration files or environment variables.

=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2009, cPanel, Inc. All rights reserved.
This code is subject to the cPanel license. Unauthorized copying is prohibited
