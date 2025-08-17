#!/usr/bin/env nu
############################################################################
# Copyright © 2025  Daniel Braniewski                                      #
#                                                                          #
# This program is free software: you can redistribute it and/or modify     #
# it under the terms of the GNU Affero General Public License as           #
# published by the Free Software Foundation, either version 3 of the       #
# License, or (at your option) any later version.                          #
#                                                                          #
# This program is distributed in the hope that it will be useful,          #
# but WITHOUT ANY WARRANTY; without even the implied warranty of           #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the             #
# GNU Affero General Public License for more details.                      #
#                                                                          #
# You should have received a copy of the GNU Affero General Public License #
# along with this program.  If not, see <https://www.gnu.org/licenses/>.   #
############################################################################


let path_template_src = "utils/template.md"
let path_template_dst = "content/template.md"

cp --verbose --force --update $path_template_src $path_template_dst

print $"Article template ready. Now, change '($path_template_dst)'s name and content."