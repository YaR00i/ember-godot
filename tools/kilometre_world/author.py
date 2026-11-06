"""Edit the kilometre recipe and build the same playable location as the CLI."""
import json
from pathlib import Path
import subprocess
import sys
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from PIL import Image, ImageTk

from recipe import TYPES, check_recipe

FIELDS = {"cx":"Центр X, м", "cz":"Центр Z, м", "rx":"Полуширина, м", "rz":"Полудлина, м",
          "grass":"Трава, групп/м²", "flowers":"Цветы, групп/м²", "tree":"Дубы", "birch":"Берёзы",
          "rock":"Камни", "house":"Дома", "lamp":"Фонари", "crate":"Ящики"}
NAMES = {"village":"Деревня", "forest":"Лес", "meadow":"Луг", "rocks":"Скалы", "lake":"Озеро", "mountain":"Гора"}


class Author:
    def __init__(self, root, workspace):
        self.root = root
        self.workspace = workspace
        self.path = workspace/"recipe.json"
        self.recipe = json.loads(self.path.read_text(encoding="utf-8-sig"))
        self.index = 0
        self.task = None
        root.title("Ember · Конструктор локации · 1 км²")
        self.map = tk.Canvas(root,width=440,height=440,highlightthickness=0,bg="#696f51")
        self.map.grid(row=0,column=0,sticky="n",padx=12,pady=12)
        self.map.bind("<Button-1>",self.pick)
        form = ttk.Frame(root,padding=10)
        form.grid(row=0,column=1)
        self.zone = ttk.Combobox(form,state="readonly",width=28,values=[
            NAMES[z["kind"]]+" · "+z["name"] for z in self.recipe["zones"]])
        self.zone.grid(row=0,column=0,columnspan=2,sticky="ew")
        self.zone.bind("<<ComboboxSelected>>",lambda _: self.select(self.zone.current()))
        self.fields = {}
        for row,(key,label) in enumerate(FIELDS.items(),1):
            ttk.Label(form,text=label).grid(row=row,column=0,sticky="w")
            field = ttk.Entry(form,width=10)
            field.grid(row=row,column=1,sticky="ew")
            self.fields[key] = field
        controls = ttk.Frame(root,padding=10)
        controls.grid(row=1,column=0,columnspan=2,sticky="ew")
        self.status = tk.StringVar()
        self.heightmap = None
        self.height_range = [0,180]
        self.seed = tk.StringVar()
        ttk.Label(controls,text="Seed (пусто — случайный)").grid(row=0,column=0)
        ttk.Entry(controls,textvariable=self.seed,width=16).grid(row=0,column=1)
        ttk.Button(controls,text="Выбрать PNG высот",command=self.choose_image).grid(row=0,column=2)
        ttk.Button(controls,text="Случайный рельеф",command=self.procedural).grid(row=0,column=3)
        ttk.Button(controls,text="Собрать локацию",command=self.generate).grid(row=1,column=0,pady=7)
        ttk.Button(controls,text="Играть",command=self.play).grid(row=1,column=1)
        ttk.Label(controls,textvariable=self.status,wraplength=670).grid(row=2,column=0,columnspan=4,sticky="w")
        self.background = None
        self.refresh()
        self.select(0,save=False)

    def refresh(self):
        project = self.workspace/"project"
        active = project/"active-world.txt"
        if active.exists():
            directory = project/active.read_text().strip().removeprefix("res://")
            world = json.loads((directory/"world.json").read_text("utf8"))
            self.seed.set(str(world["seed"]))
            self.heightmap = str(directory/"source.png") if (directory/"source.png").is_file() else None
            self.height_range = world.get("import_range_m",[0,180])
            preview = directory/"overview.png"
            self.background = ImageTk.PhotoImage(Image.open(preview if preview.exists() else directory/"color.png").resize((440,440)))
            self.status.set(f"Готовый мир · seed {world['seed']} · объектов {len(world['props'])}. Щёлкни область на карте.")

    def draw(self):
        self.map.delete("all")
        if self.background:self.map.create_image(0,0,anchor="nw",image=self.background)
        for i,zone in enumerate(self.recipe["zones"]):
            x,z,rx,rz = (zone[k]*0.44 for k in ("cx","cz","rx","rz"))
            shape = self.map.create_rectangle if zone["shape"]=="box" else self.map.create_oval
            shape(x-rx,z-rz,x+rx,z+rz,width=3 if i==self.index else 1,outline="white" if i==self.index else "#d7cfad")
            self.map.create_text(x,z,text=NAMES[zone["kind"]],fill="white")

    def store(self):
        zone = self.recipe["zones"][self.index]
        updated = {**zone,"props":dict(zone["props"])}
        for key,entry in self.fields.items():
            if key in TYPES:updated["props"][key] = int(entry.get())
            else:updated[key] = float(entry.get().replace(",","."))
        zones = self.recipe["zones"].copy()
        zones[self.index] = updated
        check_recipe({**self.recipe,"zones":zones})
        self.recipe["zones"] = zones

    def select(self, index, save=True):
        if save:
            try:self.store()
            except (TypeError,ValueError) as exc:
                self.zone.current(self.index)
                messagebox.showerror("Проверь параметры",str(exc))
                return
        self.index = index
        self.zone.current(index)
        zone = self.recipe["zones"][index]
        for key,field in self.fields.items():
            field.delete(0,"end")
            field.insert(0,str(zone["props"].get(key,0) if key in TYPES else zone[key]))
        self.draw()

    def pick(self,event):
        for i,zone in reversed(list(enumerate(self.recipe["zones"]))):
            x = (event.x/0.44-zone["cx"])/zone["rx"]
            z = (event.y/0.44-zone["cz"])/zone["rz"]
            if (max(abs(x),abs(z))<=1 if zone["shape"]=="box" else x*x+z*z<=1):
                self.select(i)
                break

    def choose_image(self):
        path = filedialog.askopenfilename(filetypes=[("PNG высот","*.png")])
        if path:
            self.heightmap = path
            self.height_range = [0,180]
            self.status.set(f"Карта высот {Path(path).name} · чёрный 0 м, белый 180 м")

    def procedural(self):
        self.heightmap = None
        self.status.set("Процедурный рельеф. С тем же seed форма повторится.")

    def command(self,action):
        return [sys.executable,str(Path(__file__).with_name("run.py")),action,"--workspace",str(self.workspace)]

    def generate(self):
        if self.task:return
        args = self.command("generate")
        try:
            self.store()
            if self.seed.get().strip():args += ["--seed",str(int(self.seed.get()))]
        except (TypeError,ValueError) as exc:
            messagebox.showerror("Проверь параметры",str(exc))
            return
        if self.heightmap:
            args += ["--heightmap",self.heightmap,"--min-height",str(self.height_range[0]),"--max-height",str(self.height_range[1])]
        self.path.write_text(json.dumps(self.recipe,ensure_ascii=False,indent=2),"utf8")
        self.status.set("Собираю рельеф, объекты и уровни детализации…")
        self.task = subprocess.Popen(args)
        self.root.after(400,self.poll)

    def poll(self):
        code = self.task.poll()
        if code is None:
            self.root.after(400,self.poll)
            return
        self.task = None
        if code:
            self.status.set("Сборка не удалась. Подробности в окне запуска. Предыдущая карта доступна.")
        else:
            self.refresh()
            self.draw()

    def play(self):
        if not self.task:subprocess.Popen(self.command("play"))


if __name__ == "__main__":
    root = tk.Tk()
    Author(root,Path(sys.argv[1]).resolve())
    root.mainloop()
