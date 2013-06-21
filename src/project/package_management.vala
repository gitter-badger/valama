/*
 * src/project/package_management.vala
 * Copyright (C) 2013, Valama development team
 *
 * Valama is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Valama is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

using Gee;

/**
 * Vala package alternatives.
 */
public class PkgChoice {
    /**
     * Indicate if all packages should go to build system package list.
     */
    //TODO: Do we need this?
    public bool all = false;
    /**
     * Ordered list of packages. Packages in the front have higher
     * priority.
     */
    public Gee.ArrayList<PackageInfo?> packages { get; private set; }
    /**
     * Optional description.
     */
    public string? description = null;

    public PkgChoice() {
        packages = new Gee.ArrayList<PackageInfo?>();
    }

    /**
     * Automatically add {@link PkgChoice} reference to each
     * {@link PackageInfo} object.
     *
     * @param pkg Package to add to package choices list.
     */
    public inline void add_package (PackageInfo pkg) {
        pkg.choice = this;
        packages.add (pkg);
    }

    /**
     * Remove {@link PackageInfo} object from choices list.
     *
     * @param pkg Package choice.
     * @return `false` if choices list is empty after operation, else `true`.
     */
    public inline bool remove_package (PackageInfo pkg) {
        packages.remove (pkg);
        if (packages.size == 0)
            return false;
        return true;
    }
}

public class PkgCheck {
    public Gee.ArrayList<PackageInfo> packages { get; private set; }
    public string? custom_vapi { get; set; default = null; }
    public string? define { get; set; default = null; }
    public string? description { get; set; default = null; }

    public PkgCheck() {
        packages = new Gee.ArrayList<PackageInfo>();
    }

    public inline void add_package (PackageInfo package) {
        packages.add (package);
    }

    public inline bool remove_package (PackageInfo package) {
        packages.remove (package);
        if (packages.size == 0)
            return false;
        return true;
    }

    public bool check (ref string? custom_vapi, ref TreeSet<string> defines) {
        foreach (var pkg in packages) {
            if (!pkg.check_available())
                return false;
            if (this.custom_vapi != null)
                //TODO: Support for multiple custom vapis? Could be done with
                //      multiple checks/pkgs though.
                custom_vapi = this.custom_vapi;
            if (define != null)
                defines.add (define);
            /*
             *NOTE: Currently extrachecks are optional and if no check at all
             * succeeds it won't result to failure.
             */
            // bool found = true;
            if (pkg.extrachecks != null) {
                // found = false;
                foreach (var check in pkg.extrachecks)
                    if (check.check (ref custom_vapi, ref defines)) {
                        // found = true;
                        break;
                    }
            }
            // if (!found)
            //     return false;
        }
        return true;
    }

    public string to_string() {
        var strb = new StringBuilder();
        for (int i = 0;  i < packages.size; ++i) {
            if (i != 0)
                strb.append (", ");
            strb.append (packages[i].to_string());
        }
        if (custom_vapi != null || define != null || description != null) {
            var start = false;
            if (packages.size > 0)
                strb.append (" - ");
            if (custom_vapi != null) {
                if (!start)
                    start = true;
                else
                    strb.append (" ");
                strb.append (_("vapi: ") + custom_vapi);
            }
            if (define != null) {
                if (!start)
                    start = true;
                else
                    strb.append (", ");
                strb.append (_("define: ") + define);
            }
            if (description != null) {
                if (!start)
                    start = true;
                else
                    strb.append (" ");
                strb.append (@"($description)");
            }
        }
        return strb.str;
    }
}

/**
 * Vala package information.
 */
public class PackageInfo {
    /**
     * Reference to {@link PkgChoice} if any.
     *
     * Do not modify this value manually. It will result in undefined behaviour.
     */
    public virtual PkgChoice? choice { get; set; default = null; }
    /**
     * Version relation.
     */
    public virtual VersionRelation? rel { get; set; default = null; }
    /**
     * Package name.
     */
    public virtual string name { get; set; }
    /**
     * Version (meaning differs with {@link rel}).
     */
    public virtual string? version { get; set; default = null; }
    /**
     * Currently available version on system.
     */
    public virtual string? current_version { get; set; default = null; }
    /**
     * Custom vapi (path) for this package.
     */
    public virtual string? custom_vapi { get; set; default = null; }
    /**
     * If `true` save custom vapi. Disable if vapi is enabled by extracheck.
     */
    public bool save_vapi { get; set; default = true; }
    /**
     * Disable checking of package dependencies.
     */
    public virtual bool? nodeps { get; set; default = null; }
    /**
     * Define related to package.
     */
    public virtual string? define { get; set; default = null; }
    /**
     * Ordered list of additional package relation checks.
     *
     * Also package relations with different packages. Helps to use custom
     * vapis only for specific versions and set defines.
     */
    public virtual Gee.ArrayList<PkgCheck>? extrachecks { get; set; default = null; }

    /**
     * Test if package is available.
     *
     * Use pkg-config to check version. If no .pc file is available always
     * true.
     *
     * @param recheck If `true` don't use cached version.
     *
     * @return `true` if available else `false`.
     */
    public bool check_available (bool recheck = true) {
        if (version == null)
            return true;

        string? vapi = (custom_vapi == null) ? Guanako.get_vapi_path (name)
                                            // NOTE: Be careful, project initialization dependency.
                                             : project.get_absolute_path (custom_vapi);
        if (vapi == null || !FileUtils.test (vapi, FileTest.EXISTS)) {
            debug_msg_level (2, _("Vapi not found for %s: %s\n"), name, vapi);
            return false;
        }

        if (current_version == null || recheck) {
            string? curversion;
            if (!package_exists (name, out curversion)) {
                debug_msg (_("Could not find pkg-config file for '%s'. Assume package exists.\n"), name);
                return true;
            } else {
                current_version = curversion;
                if (curversion == null)
                    return false;
            }
        }

        bool ret;
        switch (rel) {
            case VersionRelation.AFTER:
                ret = comp_version (current_version, version) > 0;
                break;
            case VersionRelation.SINCE:
                ret = comp_version (current_version, version) >= 0;
                break;
            case VersionRelation.BEFORE:
                ret = comp_version (current_version, version) < 0;
                break;
            case VersionRelation.UNTIL:
                ret = comp_version (current_version, version) <= 0;
                break;
            case VersionRelation.EXCLUDE:
                ret = comp_version (current_version, version) != 0;
                break;
            case VersionRelation.ONLY:
                ret = comp_version (current_version, version) == 0;
                break;
            default: // null
                ret = comp_version (current_version, version) >= 0;
                break;
        }
        if (ret)
            return true;
        else {
            debug_msg_level (2, _("Incompatible version for package '%s' %s %s found: %s\n"),
                       name,
                       (rel != null) ? VersionRelation.to_string_symbol (rel)
                                     : ">=",
                       version,
                       current_version);
            return false;
        }
    }

    /**
     * Convert class object to string.
     */
    public string to_string() {
        var strb = new StringBuilder (name);
        strb.append (to_string_version());
        return strb.str;
    }

    public string to_string_full() {
        var strb = new StringBuilder (name);
        var need_space = false;
        var need_close = false;

        if (current_version != null) {
            strb.append (current_version);
            need_space = true;
        }

        if (need_space)
            strb.append (" ");
        strb.append (to_string_version());
        need_space = true;

        if (define != null) {
            need_close = true;
            strb.append (" {");
            strb.append (define);
        }

        if (custom_vapi != null) {
            if (!need_close) {
                strb.append (" {");
                need_close = true;
            } else
                strb.append (", ");
            strb.append (custom_vapi);
        }

        if (need_close)
            strb.append ("}");
        return strb.str;
    }

    private string to_string_version() {
        var strb = new StringBuilder();
        if (rel != null) {
            strb.append (@" $(VersionRelation.to_string_symbol (rel)) ");
            if (version != null)
                strb.append (version);
        } else if (version != null) {
            strb.append (" >= ");
            strb.append (version);
        }
        return strb.str;
    }

    /**
     * Compare {@link PackageInfo} objects.
     *
     * @param pkg1 First package.
     * @param pkg2 Second package.
     * @return Return > 0 if pkg1 > pkg2, < 0 if pkg1 < pkg2 or 0 if pkg1 == pkg2.
     */
    public static int compare_func (PackageInfo pkg1, PackageInfo pkg2) {
        int namerel = strcmp (pkg1.name, pkg2.name);
        if (namerel != 0)
            return namerel;

        int verrel = comp_version (pkg1.version, pkg2.version);
        if (verrel != 0)
            return verrel;

        if (pkg1.rel != null && pkg2.rel != null) {
            int relrel = pkg1.rel - pkg2.rel;
            if (relrel != 0)
                return relrel;
        } else if (pkg1.rel != null)
            return 1;
        else if (pkg2.rel != null)
            return -1;

        return 0;
    }
}
