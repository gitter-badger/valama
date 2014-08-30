namespace Units {

  public class CodeContextProvider : Unit {
    //public Vala.CodeContext context;
    public Vala.Symbol root = null;
    public Report report = new Report();
    
    public signal void context_updated();
    
    public override void init() {
      main_widget.main_toolbar.selected_target_changed.connect(update_code_context);
      main_widget.project.member_data_changed.connect((sender, member)=>{
        if (member == current_target)
          update_code_context();
      });
      update_code_context();
    }
    public override void destroy() {
    }

    private Project.ProjectMemberTarget current_target;

    bool update_queued = false;
    bool timeout_active = false;
    public void queue_update () {
      update_queued = true;
      if (!timeout_active)
        update_code_context();
    }

    private void update_code_context() {
      timeout_active = true;
      update_queued = false;

      new Thread<int> ("Context updater", update_code_context_work);
    }

    private int update_code_context_work() {
      current_target = main_widget.main_toolbar.selected_target;
      if (current_target == null)
        return -1;
      Vala.CodeContext context_internal = new Vala.CodeContext();
      var report_internal = new Report();
      
      context_internal.profile = Vala.Profile.GOBJECT;
      context_internal.add_define ("GOBJECT");

      context_internal.target_glib_major = 2;
      context_internal.target_glib_minor = 18;

      string pkgs[8] = {"glib-2.0", "gobject-2.0", "libxml-2.0",
                        "gee-0.8", "gtk+-3.0", "gtksourceview-3.0", "libvala-0.22", "clutter-gtk-1.0"};

      foreach (string pkg in pkgs) {
        context_internal.add_external_package (pkg);
      }
      
      foreach (string source_id in current_target.included_sources) {
        var source = main_widget.project.getMemberFromId (source_id) as Project.ProjectMemberValaSource;

			  var source_file = new Vala.SourceFile (context_internal, Vala.SourceFileType.SOURCE, source.filename, source.buffer.text, false);
			  source_file.relative_filename = source.filename;

			  var ns_ref = new Vala.UsingDirective (new Vala.UnresolvedSymbol (null, "GLib", null));
			  source_file.add_using_directive (ns_ref);
			  context_internal.root.add_using_directive (ns_ref);

        context_internal.add_source_file (source_file);
      }

      var parser = new Vala.Parser();
      context_internal.report = report_internal;

      Vala.CodeContext.push (context_internal);
      parser.parse (context_internal);
      context_internal.check ();
      Vala.CodeContext.pop();
      
      //context = context_internal;
      report = report_internal;
      //stdout.printf ("old refcound: " + root.ref_count + "\n");
      root = context_internal.root;

      GLib.Idle.add (()=>{
        context_updated();
        return false;
      });
     
      GLib.Timeout.add_seconds (5, ()=> {
        if (update_queued)
          update_code_context();
        timeout_active = false;
        return false;
      });
      return 0;
    }
  }

}
