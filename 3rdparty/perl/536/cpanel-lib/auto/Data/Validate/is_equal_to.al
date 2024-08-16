# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 621 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_equal_to.al)"
# -------------------------------------------------------------------------------


sub is_equal_to{
	my $self = shift if ref($_[0]);
	my $value = shift;
	my $target = shift;
	
	# value and target must be defined
	return unless defined $value;
	return unless defined $target;
	
	if(defined(is_numeric($value)) && defined(is_numeric($target))){
		return $target if $value == $target;
	} else {
		# string comparison
		return $target if $value eq $target;
	}
	
	return;
}

# end of Data::Validate::is_equal_to
1;
