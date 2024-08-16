package Whostmgr::Docs::TweakSettings;

# cpanel - Whostmgr/Docs/TweakSettings.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Whostmgr::Theme    ();
use Cpanel::YAML::Syck ();
use strict;
my $cfg_docs;

sub fetch_key {
    my $ref = shift;

    my $section = $ref->{'section'};
    $section =~ s/\///g;

    my $texts_file = Whostmgr::Theme::find_file_path("tweaksettings/$section.yaml");

    $cfg_docs->{$texts_file} ||= YAML::Syck::LoadFile($texts_file);

    return $cfg_docs->{$texts_file}->{ $ref->{'key'} } || '';
}

1;
