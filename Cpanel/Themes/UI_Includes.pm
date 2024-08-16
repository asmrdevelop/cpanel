package Cpanel::Themes::UI_Includes;

# cpanel - Cpanel/Themes/UI_Includes.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Themes::Fallback ();
use Cpanel::SafeDir::Read    ();

=head1 NAME

Cpanel::Themes::UI_Includes - Helper object to help process UI Includes in cPanel Templates.

=head1 SYNOPSIS

    my $ui_includes = Cpanel::Themes::UI_Includes->new(
        {
            'username' => $Cpanel::user,
            'owner'    => $Cpanel::CPDATA{'OWNER'} || 'root',
            'theme'    => $Cpanel::CPDATA{'RS'},
        }
    );
    # To use the default include paths, you can use (see L<Cpanel::Themes::Fallback::get_paths()>)
    $ui_includes->set_include_paths();

    # To specify custom paths, you can use
    $ui_includes->set_include_paths(\@paths_to_include);

    # get the include paths for a template file:
    $ui_includes->path_for_file('template_filename.tmpl');

=head1 METHODS

=over 8

=item B<new>

Constructor.

B<Args>:

One required argument: a hashref with the following keys

    username
    owner
    theme

=cut

sub new {
    my ( $class, $opts ) = @_;
    _check_opts_passed($opts);

    my $self = {
        'username'      => $opts->{'username'},
        'owner'         => $opts->{'owner'},
        'theme'         => $opts->{'theme'},
        'include_paths' => undef,
    };
    return bless $self, $class;
}

=item B<set_include_paths>

Object method. Sets the include paths that will be checked on subsequent L<path_for_file> calls.

B<Args>:

One optional argument: An arrayref to set of include paths to use.

=cut

sub set_include_paths {
    my ( $self, $paths ) = @_;

    if ( not( $paths and ref $paths eq 'ARRAY' ) ) {
        my @paths = Cpanel::Themes::Fallback::get_paths(
            'username'          => $self->{'username'},
            'owner'             => $self->{'owner'},
            'theme'             => $self->{'theme'},
            'no_user_directory' => 1,
            'subdirectory'      => 'includes',
        );
        $self->{'include_paths'} = \@paths;
    }
    else {
        $self->{'include_paths'} = $paths;
    }

    return 1;
}

=item B<get_include_paths>

Object method. Returns the include paths configured in the object.

B<Args>: none

Calls L<set_include_paths> without any arguments if the include paths are not already populated.

=cut

sub get_include_paths {
    my $self = shift;

    $self->set_include_paths() if not( $self->{'include_paths'} and ref $self->{'include_paths'} eq 'ARRAY' );
    return $self->{'include_paths'};
}

=item B<path_for_file>

Object method. Returns the first path in the configured include paths where the template file is found.

Returns undef if template is not found in the include paths.

B<Args>:

One required argument: the filename of the template.

=cut

sub path_for_file {
    my ( $self, $file ) = @_;
    for my $path ( @{ $self->get_include_paths } ) {
        $self->{'_include_path_cache'}{$path} ||= { map { $_ => undef } Cpanel::SafeDir::Read::read_dir($path) };
        return $path if exists $self->{'_include_path_cache'}{$path}{$file};
    }
    return;
}

sub _check_opts_passed {
    my $opts = shift;
    die 'Constructor must be passed a HASHREF' if not( $opts and ref $opts eq 'HASH' );
    foreach my $opt (qw/username owner theme/) {
        die "Missing required option: '$opt'" if not defined $opts->{$opt};
    }

    return;
}

=back

=cut

1;
