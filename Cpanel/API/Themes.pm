package Cpanel::API::Themes;

# cpanel - Cpanel/API/Themes.pm                     Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::AdminBin::Call    ();
use Cpanel::Logger::Soft      ();
use Cpanel::Themes::Available ();

use Cpanel::Locale 'lh';

=head1 NAME

Cpanel::API::Themes

=head1 DESCRIPTION

UAPI functions related to the theme management.

=head2 update

=head3 Purpose

Allow a user to change their theme.

=head3 Arguments

  theme - the theme to change the user to (e.g., jupiter).

=head3 Returns

=cut

sub update {
    my ($args) = @_;

    my $theme = $args->get('theme');

    Cpanel::AdminBin::Call::call( 'Cpanel', 'user', 'CHANGE_THEME', $theme );

    return 1;
}

=head2 list

=head3 Purpose

Get a list of the themes available to user

=head3 Arguments

  show_mail_themes - int boolean indicating whether mail only themes should be hidden

=head3 Returns

  array - list of themes, f.ex:  [ 'jupiter' ]

=cut

sub list {
    my ( $args, $result ) = @_;

    my $show_mail_themes = $args->get('show_mail_themes');
    my $data             = Cpanel::Themes::Available::get_available_themes();

    if ( !$show_mail_themes ) {
        $data = [ grep { $_ !~ /mail$/ } @{$data} ];
    }

    # Include current theme, if it's not listed.
    if ( $Cpanel::CPDATA{'RS'} && !grep { $_ eq $Cpanel::CPDATA{'RS'} } @{$data} ) {
        push @{$data}, $Cpanel::CPDATA{'RS'};
    }

    $result->data($data);
    return 1;
}

=head2 get_theme_base

=head3 DEPRECATED

C<Cpanel::API::Themes::get_theme_base> is deprecated.

=head3 Purpose

Get the name of the base theme for the current theme. This is based on a best guess using
key directory locations that have remained fairly static for each of the main themes
we are currently supporting.

=head3 Arguments

None

=head3 Returns

  string - name of the base theme. May be one of:

=over 2

=item B<jupiter> - The theme is recognized as the jupiter theme or a theme cloned from jupiter.

=item B<unknown> - The theme is an unrecognized theme.

=back

=cut

sub get_theme_base {
    my ( $args, $result ) = @_;

    Cpanel::Logger::Soft::deprecated('The Themes::get_theme_base method is deprecated.');

    if ( $Cpanel::appname eq 'whostmgrd' ) {
        $result->error('WHM does not support the [asis,Cpanel::Themes::get_theme_base()] function.');
        return;
    }

    my $theme = $Cpanel::CPDATA{'RS'};

    if ( $theme eq 'jupiter' ) {

        # If we already have a distributed theme, we're done
        $result->data($theme);
        return 1;
    }

    my $app_dir  = $Cpanel::appname eq 'webmail' ? "webmail" : "frontend";
    my $ulc_dir  = _get_ulc();
    my $root_dir = "$ulc_dir/base/$app_dir/$theme";

    # Heuristic directories
    my $assets_test = "$root_dir/_assets/";

    # Lets make this test most efficient for jupiter since its the current distributed theme.
    if ( -d $assets_test ) {
        $result->data('jupiter');
        return 1;
    }

    $result->data('unknown');
    return 1;
}

# For unit testing
sub _get_ulc {
    return "/usr/local/cpanel";
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    update         => $allow_demo,
    list           => $allow_demo,
    get_theme_base => $allow_demo,
);

1;

