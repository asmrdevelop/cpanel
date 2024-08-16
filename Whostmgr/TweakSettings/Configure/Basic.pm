package Whostmgr::TweakSettings::Configure::Basic;

# cpanel - Whostmgr/TweakSettings/Configure/Basic.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Whostmgr::TweakSettings::Configure::Base';

use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Config::SaveWwwAcctConf ();

=encoding utf-8

=head1 NAME

Whostmgr::TweakSettings::Configure::Basic - Module for applying 'Basic' tweak settings.

=head1 SYNOPSIS

    Whostmgr::TweakSettings::apply_module_settings('Basic', {'key'=>'value'});

=head1 DESCRIPTION

This module is not intended to be called directly and should only
be called via Whostmgr::TweakSettings.

=head2 new

Creates a new Whostmgr::TweakSettings::Configure::Basic object
Only intended to be called from Whostmgr::TweakSettings

=cut

sub new {
    my ($class) = @_;
    my $data = scalar Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    return bless {
        '_data'          => {%$data},
        '_original_data' => {%$data},
    }, $class;
}

=head2 save

Save the 'Basic' tweak settings.
Only intended to be called from Whostmgr::TweakSettings

=cut

sub save {
    Cpanel::Config::LoadWwwAcctConf::reset_mem_cache();
    return Cpanel::Config::SaveWwwAcctConf::savewwwacctconf( $_[0]->{'_data'} );
}

1;
