package Whostmgr::Templates::Chrome;

# cpanel - Whostmgr/Templates/Chrome.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FileUtils::Write           ();
use Cpanel::LoadModule                 ();
use Cpanel::Template                   ();
use Cpanel::CSP::Nonces                ();
use Cpanel::Template::Plugin::Whostmgr ();

use Whostmgr::Templates::Chrome::Directory ();
use Whostmgr::Templates::Command           ();
use Whostmgr::Theme                        ();

=head1 DESCRIPTION

Utility functions to process and cache WHM chrome (footer and header).

=cut

=head1 SUBROUTINES

=cut

sub _get_footer_cache_dir {
    return Whostmgr::Templates::Chrome::Directory::get_footer_cache_directory();
}

sub _get_header_cache_dir {
    return Whostmgr::Templates::Chrome::Directory::get_header_cache_directory();
}

=head2 process_footer

=head3 Purpose

Process _deffooter.tmpl and save result on disk

=cut

sub process_footer {
    my $cache_dir = _get_footer_cache_dir();
    if ( !-e $cache_dir ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::SafeDir::MK::safemkdir( $cache_dir, '0700' );
    }

    my $save_file = $cache_dir . '/footer.html';

    return 1 if -e $save_file;

    _process_and_save_template( '_deffooter.tmpl', {}, $save_file );

    return 1;
}

=head2 process_header

=head3 Purpose

Process _defheader.tmpl and save result on disk

=head3 Arguments

=over

=item skipsupport    => hides support tab

=item skipheader     => hides header icon/text

=back

=cut

sub process_header {
    my ($args) = @_;

    $args->{'skipsupport'} = $args->{'skipsupport'} ? 1 : 0;
    $args->{'skipheader'}  = $args->{'skipheader'}  ? 1 : 0;

    my $cache_dir = _get_header_cache_dir();
    if ( !-e $cache_dir ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::SafeDir::MK::safemkdir( $cache_dir, '0700' );
    }

    my $save_file = $cache_dir . '/' . Whostmgr::Templates::Command::get_cache_key();
    $save_file .= '_' . $args->{'skipsupport'};
    $save_file .= '_' . $args->{'skipheader'};
    $save_file .= '.html';

    return 1 if -e $save_file && !-z _;    # Some of these cache files were generated empty, this insures they will get regenerated.

    _process_and_save_template( '_defheader.tmpl', $args, $save_file );

    return 1;
}

sub _process_and_save_template {
    my ( $template, $args, $save_file ) = @_;
    my $real_user = $ENV{'REMOTE_USER'};

    # not going to find theme for a dummy user
    no warnings 'redefine';
    local *Whostmgr::Theme::gettheme                         = sub { return 'x'; };
    local *Cpanel::CSP::Nonces::nonce                        = sub { return '00000000000'; };    # Provide a placeholder for nonces generated in the header.
    local *Cpanel::Template::Plugin::Whostmgr::get_favorites = sub { return 'dynamic'; };
    use warnings 'redefine';

    local $ENV{'cp_security_token'} = '/cpsess0000000000';
    local $ENV{'SCRIPT_NAME'}       = $ENV{'cp_security_token'} . '/';                           # get rid of warning from Cpanel/Template/Plugin/Whostmgr.pm
    local $ENV{'REMOTE_USER'}       = 'cpuser00000000000';

    my ( $status, $tmpl_data ) = Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => $template,
            'theme'         => 'bootstrap',
            'print'         => 0,
            %$args,
        }
    );

    if ( !$status ) {
        warn "Failed to generated the header for '$real_user' reseller: $tmpl_data";
        return;
    }

    eval { Cpanel::FileUtils::Write::overwrite( $save_file, $$tmpl_data, 0600 ) };
    if ( my $exception = $@ ) {
        warn "Failed to save the cached header for '$real_user' reseller: " . $exception->to_string();
    }

    return;
}

1;
