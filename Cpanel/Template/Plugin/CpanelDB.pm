package Cpanel::Template::Plugin::CpanelDB;

# cpanel - Cpanel/Template/Plugin/CpanelDB.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: This is a base class, but it can be instantiated as well.
#----------------------------------------------------------------------

use strict;
use warnings;

use base 'Template::Plugin';

sub PREFIX_LENGTH {
    require Cpanel::DB::Prefix;
    return Cpanel::DB::Prefix::get_prefix_length();
}

sub MAX_MYSQL_DBUSER_LENGTH {
    require Cpanel::Validate::DB::User;
    return Cpanel::Validate::DB::User::get_max_mysql_dbuser_length();
}

sub dbownerprefix {
    require Cpanel::DB;
    my $dbownerprefix = Cpanel::DB::get_prefix() || q<>;

    return $dbownerprefix ? "$dbownerprefix\_" : undef;
}

sub use_prefix {
    require Cpanel::DB::Prefix::Conf;
    goto \&Cpanel::DB::Prefix::Conf::use_prefix;
}

#For subclasses. Ideally this would go into a mix-in class, but
#that seems a bit pedantic here.
sub _required_password_strength {
    my ($self) = @_;
    require Cpanel::PasswdStrength::Check;
    return Cpanel::PasswdStrength::Check::get_required_strength( $self->_PASSWORD_STRENGTH_APP() );
}

1;
