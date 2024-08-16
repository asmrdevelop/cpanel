# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 674 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_even.al)"
# -------------------------------------------------------------------------------


sub is_even{
	my $self = shift if ref($_[0]);
	my $value = shift;
	
	return unless defined(is_numeric($value));
	my $untainted = is_integer($value);
	return unless defined($untainted);
	
	return $untainted unless $value % 2;
	
	return;
}

# end of Data::Validate::is_even
1;
