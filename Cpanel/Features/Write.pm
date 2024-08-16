package Cpanel::Features::Write;

# cpanel - Cpanel/Features/Write.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Features::Load      ();
use Cpanel::Config::FlushConfig ();

sub featurelist_file {
    my $file = $_[0];
    $file =~ s/\///g;
    return $Cpanel::Features::Load::feature_list_dir . '/' . $file;
}

sub write_featurelist {
    my ( $name, $feature_ref ) = @_;

    my $file = featurelist_file($name);

    foreach my $key ( keys %{$feature_ref} ) {
        $feature_ref->{$key} =~ s/\r\n/\n/g;
        $feature_ref->{$key} =~ s/\r//g;
        $feature_ref->{$key} =~ s/\n+/\n/g;
    }

    Cpanel::Config::FlushConfig::flushConfig( $file, $feature_ref, '=' );
}

1;    # Magic true value required at end of module
