package Cpanel::Exception::Database::TableCorruption;

# cpanel - Cpanel/Exception/Database/TableCorruption.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#----------------------------------------------------------------------
#TODO: This is an example of an error that, because there is a potentially
#large amount of data involved, is ideally displayed as a data structure
#rather than as a simple string. Currently our APIs and AdminBin don't
#accommodate the idea of error metadata, though this is probably something
#that warrants implementation.
#----------------------------------------------------------------------

#Metadata propreties:
#   table_error - hashref of (table name => error string)
#
sub _default_phrase {
    my ($self) = @_;

    my $reason_hr = $self->{'_metadata'}{'table_error'};

    #NOTE: "$foo ($bar)" may be considered a partial phrase that should be
    #localized separately.
    my @tables_disp = map { "$_ ($reason_hr->{$_})" } sort keys %$reason_hr;

    return Cpanel::LocaleString->new(
        'The system detected corruption in the following [numerate,_1,table,tables]: [list_and,_2]',
        ( scalar @tables_disp ),
        \@tables_disp,
    );
}

1;
