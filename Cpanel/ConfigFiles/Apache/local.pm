package Cpanel::ConfigFiles::Apache::local;

# cpanel - Cpanel/ConfigFiles/Apache/local.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

######################################################################################################
#### This module is a modified version of EA3’s distiller’s code, it will be cleaned up via ZC-5317 ##
######################################################################################################

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ConfigFiles::Apache::local - Information about apache .local templates

=head1 SYNOPSIS

    use Cpanel::ConfigFiles::Apache::local;

    my @list_if_installed_dot_local_apache_template =
    Cpanel::ConfigFiles::Apache::local::get_installed_local_apache_template_paths();

=head1 DESCRIPTION

This module provides information about installed apache
.local template files.

We currently use this to provide warnings that these
templates need to be maintained by the server owner
and avoid enabling new features that require template
changes.

=cut

#NB: Duplicated with:
#   - Cpanel::Template
#   - Cpanel::ConfigFiles::Apache::vhost::render_vhost()
#
our @possible_templates = (
    qw(
      /var/cpanel/templates/apache2_4/ea4.custom
      /var/cpanel/templates/apache2_4/ea4_main.local

      /var/cpanel/templates/apache2_4/ea4.ssl_vhost.custom
      /var/cpanel/templates/apache2_4/ssl_vhost.local

      /var/cpanel/templates/apache2_4/ea4.vhost.custom
      /var/cpanel/templates/apache2_4/vhost.local
    )
);

=head2 get_installed_local_apache_template_paths()

Returns a list of installed apache .local template
files on this system.

=cut

sub get_installed_local_apache_template_paths {
    return grep { -e } @possible_templates;
}

1;
