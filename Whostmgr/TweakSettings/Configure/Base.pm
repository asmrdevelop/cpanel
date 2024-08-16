package Whostmgr::TweakSettings::Configure::Base;

# cpanel - Whostmgr/TweakSettings/Configure/Base.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::TweakSettings::Configure::Base - A base class for Whostmgr::TweakSettings::Configure modules

=head1 SYNOPSIS

    use parent 'Whostmgr::TweakSettings::Configure::Base';

=cut

use Cpanel::Exception ();

sub new {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 pre_process

When saving tweaksettings values, this method is called to
ensure the data is in order.  In practice this method is mostly
used to deal with legacy inputs.

=cut

sub pre_process {
    return;
}

=head2 get_conf

Returns the current configuration key value pairs
for the module.  Modules are expected to store the
data in _data.

=cut

sub get_conf {
    return $_[0]->{'_data'};
}

=head2 get_original_conf

When saving new key value pairs this function will
return the original key value pairs before they were
modified.

=cut

sub get_original_conf {
    return $_[0]->{'_original_data'};
}

=head2 set

Set a tweak setting key and value.

=cut

sub set {

    # my($self,$key,$value)= @_;
    $_[0]->{'_data'}{ $_[1] } = $_[2];
    return 1;
}

=head2 abort

Aborts modification of tweaksettings key values pairs.

=cut

sub abort {
    return;
}

=head2 save

Commits modification of tweaksettings key values pairs.

=cut

sub save {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 finish

After tweaksettings key value pairs have been saved and
post_actions have been run finish is called.

=cut

sub finish {
    return;
}

1;
