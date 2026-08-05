classdef NavigationDataApp < matlab.apps.AppBase

    properties (Access = public)
        UIFigure matlab.ui.Figure
        TabGroup matlab.ui.container.TabGroup
        BrowseTab matlab.ui.container.Tab
        BrowseGrid matlab.ui.container.GridLayout
        LibraryTree matlab.ui.container.CheckBoxTree
        BooksNode matlab.ui.container.TreeNode
        AuthorsNode matlab.ui.container.TreeNode
        SelectedItemsListBox matlab.ui.control.ListBox
        DetailsTab matlab.ui.container.Tab
        DetailsGrid matlab.ui.container.GridLayout
        CategoryButtonGroup matlab.ui.container.ButtonGroup
        FictionRadioButton matlab.ui.control.RadioButton
        NonfictionRadioButton matlab.ui.control.RadioButton
        FeatureButtonGroup matlab.ui.container.ButtonGroup
        FeaturedToggleButton matlab.ui.control.ToggleButton
        CatalogTable matlab.ui.control.Table
        DocumentationLink matlab.ui.control.Hyperlink
        CoverImage matlab.ui.control.Image
        InformationHTML matlab.ui.control.HTML
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure("Visible", "off");
            app.UIFigure.Position = [100 100 680 420];
            app.UIFigure.Name = "Navigation and Data";

            app.TabGroup = uitabgroup(app.UIFigure);
            app.TabGroup.Position = [15 15 650 390];

            app.BrowseTab = uitab(app.TabGroup);
            app.BrowseTab.Title = "Browse";

            app.BrowseGrid = uigridlayout(app.BrowseTab);
            app.BrowseGrid.ColumnWidth = {'1x', '1x'};
            app.BrowseGrid.RowHeight = {'1x'};

            app.LibraryTree = uitree(app.BrowseGrid, "checkbox");
            app.LibraryTree.Layout.Row = 1;
            app.LibraryTree.Layout.Column = 1;

            app.BooksNode = uitreenode(app.LibraryTree);
            app.BooksNode.Text = "Books";
            app.BooksNode.NodeData = "books";

            app.AuthorsNode = uitreenode(app.LibraryTree);
            app.AuthorsNode.Text = "Authors";
            app.AuthorsNode.NodeData = "authors";

            app.SelectedItemsListBox = uilistbox(app.BrowseGrid);
            app.SelectedItemsListBox.Items = ["Read later", "Favorites", "Archived"];
            app.SelectedItemsListBox.Value = "Read later";
            app.SelectedItemsListBox.Layout.Row = 1;
            app.SelectedItemsListBox.Layout.Column = 2;

            app.DetailsTab = uitab(app.TabGroup);
            app.DetailsTab.Title = "Details";

            app.DetailsGrid = uigridlayout(app.DetailsTab);
            app.DetailsGrid.ColumnWidth = {'1x', '1x'};
            app.DetailsGrid.RowHeight = {'fit', 'fit', '1x', '1x'};

            app.CategoryButtonGroup = uibuttongroup(app.DetailsGrid);
            app.CategoryButtonGroup.Title = "Category";
            app.CategoryButtonGroup.Layout.Row = 1;
            app.CategoryButtonGroup.Layout.Column = 1;

            app.FictionRadioButton = uiradiobutton(app.CategoryButtonGroup);
            app.FictionRadioButton.Text = "Fiction";
            app.FictionRadioButton.Position = [20 20 80 22];

            app.NonfictionRadioButton = uiradiobutton(app.CategoryButtonGroup);
            app.NonfictionRadioButton.Text = "Nonfiction";
            app.NonfictionRadioButton.Position = [120 20 100 22];

            app.FeatureButtonGroup = uibuttongroup(app.DetailsGrid);
            app.FeatureButtonGroup.Title = "View";
            app.FeatureButtonGroup.Layout.Row = 1;
            app.FeatureButtonGroup.Layout.Column = 2;

            app.FeaturedToggleButton = uitogglebutton(app.FeatureButtonGroup);
            app.FeaturedToggleButton.Text = "Featured";
            app.FeaturedToggleButton.Position = [20 20 100 30];

            app.CatalogTable = uitable(app.DetailsGrid);
            app.CatalogTable.ColumnName = ["Title", "Rating"];
            app.CatalogTable.Layout.Row = 2;
            app.CatalogTable.Layout.Column = [1 2];

            app.DocumentationLink = uihyperlink(app.DetailsGrid);
            app.DocumentationLink.Text = "Open catalog documentation";
            app.DocumentationLink.URL = "https://www.mathworks.com";
            app.DocumentationLink.Layout.Row = 3;
            app.DocumentationLink.Layout.Column = 1;

            app.CoverImage = uiimage(app.DetailsGrid);
            app.CoverImage.ScaleMethod = "fit";
            app.CoverImage.Layout.Row = 3;
            app.CoverImage.Layout.Column = 2;

            app.InformationHTML = uihtml(app.DetailsGrid);
            app.InformationHTML.HTMLSource = "<p>Catalog information</p>";
            app.InformationHTML.Layout.Row = 4;
            app.InformationHTML.Layout.Column = [1 2];

            app.UIFigure.Visible = "on";
        end
    end

    methods (Access = public)
        function app = NavigationDataApp
            createComponents(app);
            registerApp(app, app.UIFigure);

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end
end
