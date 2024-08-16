package Cpanel::Template::Plugin::Command;

# cpanel - Cpanel/Template/Plugin/Command.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Template::Plugin';

use Whostmgr::Templates::Command ();

my $template_data;

sub clear_cache {
    $template_data = undef;
    return;
}

=head1 DESCRIPTION

Template toolkit plugin to load cached command.tmpl

=cut

=head1 SYNOPSIS

    use Cpanel::Template::Plugin::Command ();

    my $plugin = Cpanel::Template::Plugin::Command->new();
    my $data   = $plugin->get();

=cut

=head2 get

=head3 Purpose

Retrieves cached command.tmpl data

=head3 Returns

=over

=item cached command.tmpl

=back

=cut

sub get {
    my (undef) = @_;

    return $template_data if $template_data;

    $template_data = Whostmgr::Templates::Command::cached_load();

    if ( defined $ENV{'cp_security_token'} ) {
        $template_data =~ s/\/cpsess[0-9]+/$ENV{'cp_security_token'}/g;
    }
    else {
        $template_data =~ s/\/cpsess[0-9]+//g;
    }

    return $template_data;
}

1;
